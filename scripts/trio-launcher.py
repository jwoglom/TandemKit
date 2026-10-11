#!/usr/bin/env python3
"""Installs and launches Trio in the simulator for TrioIntegrationTests, one install per test.

scripts/trio-test.sh starts this and hands its URL to the tests, which run in the simulator and
cannot reach simctl themselves. It serves HTTP on 127.0.0.1, which the simulator shares:

  POST /install?name=<test>  stop Trio, install it anew and seed its data container; a JSON body
                             {"files": {path: text}} adds or replaces files in the container
  POST /launch               launch it; a JSON body {"arguments": [...]} passes launch arguments
  POST /relaunch             stop Trio and launch it again on the same data, with the same arguments
  POST /stop                 stop Trio; {"sample": true} first samples its stacks for a few seconds

/install answers {"dataContainer": path}; /launch and /relaunch add "controlPort" once TandemKit
inside Trio accepts on it. Stopping an install copies its logs and store to LOG_DIR/<test>, with
the stack sample as trio-sample.txt.
"""

import argparse
import http.server
import json
import os
import plistlib
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

# TandemKit opens the channel when Trio creates its pump manager, after Core Data is up.
CONTROL_PORT_TIMEOUT = 180


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_port(port, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return
        except OSError:
            time.sleep(0.5)
    raise RuntimeError(f"nothing listening on 127.0.0.1:{port} after {timeout}s")


def seed(container):
    """What Trio reads at launch to start set up, with an unpaired Tandem pump manager.

    Documents/<key>.plist holds each @PersistedProperty. Both telemetry streams are on unless
    explicitly false. Trio's own settings come from the test, with its other files.
    """
    documents = Path(container) / "Documents"
    documents.mkdir(parents=True, exist_ok=True)
    plists = {
        "onboardingCompleted": True,
        "hasSeenFatProteinOrderChange": True,
        "crashlyticsSharingEnabled": False,
        "telemetrySharingEnabled": False,
        "PumpManagerState": {"managerIdentifier": "TandemPumpManager", "state": {}},
    }
    for key, value in plists.items():
        with open(documents / f"{key}.plist", "wb") as f:
            plistlib.dump(value, f)


def write_files(container, files):
    root = Path(container).resolve()
    for relative, text in files.items():
        path = (root / relative).resolve()
        if root not in path.parents:
            raise ValueError(f"{relative} is outside the data container")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


class Trio:
    def __init__(self, udid, app, bundle_id, gatt, log_dir):
        self.udid, self.app, self.bundle_id, self.gatt = udid, app, bundle_id, gatt
        self.log_dir = Path(log_dir)
        self.container = None
        self.name = None
        self.arguments = []
        self.running = False
        self.pid = None

    def simctl(self, *args, check=True):
        return subprocess.run(["xcrun", "simctl", *args], check=check, capture_output=True, text=True)

    def stop(self, sample=False):
        if sample and self.running and self.pid:
            # A Trio that stopped answering logs nothing about why; its stacks say where it is stuck.
            path = self.archive_dir() / "trio-sample.txt"
            print(f"sampling Trio ({self.pid}) into {path}", flush=True)
            subprocess.run(["sample", str(self.pid), "3", "-file", str(path)], check=False, capture_output=True, timeout=120)
        self.simctl("terminate", self.udid, self.bundle_id, check=False)
        if self.running and self.container:
            self.archive()
        self.running = False
        self.pid = None

    def archive_dir(self):
        target = self.log_dir / re.sub(r"[^A-Za-z0-9._-]+", "_", self.name or "trio").strip("_-")
        target.mkdir(parents=True, exist_ok=True)
        return target

    def archive(self):
        """Simulated data only: what a failed test's artifacts need."""
        target = self.archive_dir()
        logs = Path(self.container) / "Documents" / "logs"
        if logs.is_dir():
            shutil.copytree(logs, target / "documents-logs", dirs_exist_ok=True)
        for store in Path(self.container).rglob("TrioCoreDataPersistentContainer.sqlite*"):
            shutil.copy2(store, target)

    def install(self, name, files):
        self.stop()
        self.simctl("uninstall", self.udid, self.bundle_id, check=False)
        self.simctl("install", self.udid, self.app)
        self.container = self.simctl("get_app_container", self.udid, self.bundle_id, "data").stdout.strip()
        self.name = name
        self.arguments = []
        seed(self.container)
        write_files(self.container, files)
        return {"dataContainer": self.container}

    def launch(self, arguments):
        if not self.container:
            raise RuntimeError("no Trio installed; POST /install first")
        self.stop()
        self.arguments = arguments
        port = free_port()
        env = {
            "SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP": self.gatt,
            "SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP_CONTROL": str(port),
        }
        print(f"launching {self.bundle_id} {arguments} for {self.name}; control port {port}; data {self.container}", flush=True)
        launched = subprocess.run(
            ["xcrun", "simctl", "launch", self.udid, self.bundle_id, *arguments],
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, **env},
        )
        print(launched.stdout, end="", flush=True)
        # simctl prints "<bundle id>: <pid>".
        pid = re.search(r":\s*(\d+)\s*$", launched.stdout.strip())
        self.pid = int(pid.group(1)) if pid else None
        self.running = True
        wait_for_port(port, CONTROL_PORT_TIMEOUT)
        return {"controlPort": port, "dataContainer": self.container}


def serve(trio, port_file):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            try:
                length = int(self.headers.get("Content-Length") or 0)
                request = json.loads(self.rfile.read(length) or b"{}")
                if url.path == "/install":
                    body = trio.install(query.get("name", ["trio"])[0], request.get("files", {}))
                elif url.path == "/launch":
                    body = trio.launch(request.get("arguments", []))
                elif url.path == "/relaunch":
                    body = trio.launch(trio.arguments)
                elif url.path == "/stop":
                    trio.stop(sample=bool(request.get("sample")))
                    body = {}
                else:
                    return self.answer(404, {"error": f"no {url.path}"})
                self.answer(200, body)
            except subprocess.CalledProcessError as error:
                self.answer(500, {"error": f"{error}: {error.stderr}"})
            except Exception as error:  # noqa: BLE001 - every failure goes back to the test
                self.answer(500, {"error": str(error)})

        def answer(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format, *args):
            print(format % args, flush=True)

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)

    def shut_down(*_):
        trio.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shut_down)
    signal.signal(signal.SIGINT, shut_down)
    Path(port_file).write_text(str(server.server_address[1]))
    server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--app", required=True, help="the built Trio.app")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--gatt", required=True, help="faketandem's virtual GATT address, host:port")
    parser.add_argument("--log-dir", required=True)
    parser.add_argument("--port-file", required=True, help="written with the port once listening")
    args = parser.parse_args()
    serve(Trio(args.udid, args.app, args.bundle_id, args.gatt, args.log_dir), args.port_file)


if __name__ == "__main__":
    main()
