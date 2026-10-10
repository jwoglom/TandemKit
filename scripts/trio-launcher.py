#!/usr/bin/env python3
"""Installs and launches Trio in the simulator for TrioIntegrationTests, one install per test.

scripts/trio-test.sh starts this and hands its URL to the tests, which run in the simulator and
cannot reach simctl themselves. It serves HTTP on 127.0.0.1, which the simulator shares:

  POST /fresh?name=<test>  stop Trio, install it anew, seed its data container, launch it
  POST /relaunch           stop Trio and launch it again on the same data
  POST /stop               stop Trio

/fresh and /relaunch answer {"controlPort": n, "dataContainer": path} once TandemKit inside Trio
accepts on its control port. Stopping an install copies its logs and store to LOG_DIR/<test>.
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
    explicitly false. settings/settings.json pins the limits the tests read back, and
    basal_profile.json the rate the tests sync to the pump.
    """
    documents = Path(container) / "Documents"
    (documents / "settings").mkdir(parents=True, exist_ok=True)
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
    (documents / "settings" / "settings.json").write_text(
        json.dumps({"insulin_action_curve": 10, "maxBolus": 10, "maxBasal": 2}) + "\n"
    )
    (documents / "settings" / "basal_profile.json").write_text(
        json.dumps([{"start": "00:00:00", "minutes": 0, "rate": 1.0}]) + "\n"
    )


class Trio:
    def __init__(self, udid, app, bundle_id, gatt, log_dir):
        self.udid, self.app, self.bundle_id, self.gatt = udid, app, bundle_id, gatt
        self.log_dir = Path(log_dir)
        self.container = None
        self.name = None
        self.running = False

    def simctl(self, *args, check=True):
        return subprocess.run(["xcrun", "simctl", *args], check=check, capture_output=True, text=True)

    def stop(self):
        self.simctl("terminate", self.udid, self.bundle_id, check=False)
        if self.running and self.container:
            self.archive()
        self.running = False

    def archive(self):
        """Simulated data only: what a failed test's artifacts need."""
        target = self.log_dir / re.sub(r"[^A-Za-z0-9._-]+", "_", self.name or "trio").strip("_-")
        target.mkdir(parents=True, exist_ok=True)
        logs = Path(self.container) / "Documents" / "logs"
        if logs.is_dir():
            shutil.copytree(logs, target / "documents-logs", dirs_exist_ok=True)
        for store in Path(self.container).rglob("TrioCoreDataPersistentContainer.sqlite*"):
            shutil.copy2(store, target)

    def fresh(self, name):
        self.stop()
        self.simctl("uninstall", self.udid, self.bundle_id, check=False)
        self.simctl("install", self.udid, self.app)
        self.container = self.simctl("get_app_container", self.udid, self.bundle_id, "data").stdout.strip()
        self.name = name
        seed(self.container)
        return self.launch()

    def relaunch(self):
        if not self.container:
            raise RuntimeError("no Trio installed; POST /fresh first")
        self.stop()
        return self.launch()

    def launch(self):
        port = free_port()
        env = {
            "SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP": self.gatt,
            "SIMCTL_CHILD_TANDEMKIT_VIRTUAL_PUMP_CONTROL": str(port),
        }
        print(f"launching {self.bundle_id} for {self.name}; control port {port}; data {self.container}", flush=True)
        subprocess.run(["xcrun", "simctl", "launch", self.udid, self.bundle_id], check=True, env={**os.environ, **env})
        self.running = True
        wait_for_port(port, CONTROL_PORT_TIMEOUT)
        return {"controlPort": port, "dataContainer": self.container}


def serve(trio, port_file):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            try:
                if url.path == "/fresh":
                    body = trio.fresh(query.get("name", ["trio"])[0])
                elif url.path == "/relaunch":
                    body = trio.relaunch()
                elif url.path == "/stop":
                    trio.stop()
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
