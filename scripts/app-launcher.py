#!/usr/bin/env python3
"""Installs and launches the host app, Trio or Loop, in the simulator for TrioIntegrationTests and
LoopIntegrationTests, one install per test.

scripts/trio-test.sh and scripts/loop-test.sh start this and hand its URL to the tests, which run in
the simulator and cannot reach simctl themselves. It serves HTTP on 127.0.0.1, which the simulator
shares:

  POST /install?name=<test>  stop the app, install it anew and seed it; a JSON body
                             {"files": {path: text}, "defaults": {"app" | "group": plist text}}
                             adds or replaces files in the data container ("group:<path>" in the
                             app group container) and sets the keys of the app's or the app group's
                             UserDefaults
  POST /launch               launch it; a JSON body {"arguments": [...]} passes launch arguments
  POST /relaunch             stop it and launch it again on the same data, with the same arguments
  POST /stop                 stop it; {"sample": true} first samples its stacks for a few seconds

/install answers {"dataContainer": path, "groupContainer": path}; /launch and /relaunch add
"controlPort" once TandemKit inside the app accepts on it. Stopping an install copies its logs and
store to LOG_DIR/<test>, with the stack sample as <app>-sample.txt.
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

# TandemKit opens the channel when the app creates its pump manager, after Core Data is up.
CONTROL_PORT_TIMEOUT = 180
CONTAINER_METADATA = ".com.apple.mobile_container_manager.metadata.plist"


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


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        plistlib.dump(value, f)


class Trio:
    """Trio reads each @PersistedProperty from Documents/<key>.plist; both telemetry streams are on
    unless explicitly false. Its settings come from the test, with its other files."""

    name = "Trio"
    stores = [("data", "TrioCoreDataPersistentContainer.sqlite*")]
    logs = ["Documents/logs", "Documents/tandem"]
    fresh_group_container = False

    @staticmethod
    def seed(data, group, info):
        documents = Path(data) / "Documents"
        for key, value in {
            "onboardingCompleted": True,
            "hasSeenFatProteinOrderChange": True,
            "crashlyticsSharingEnabled": False,
            "telemetrySharingEnabled": False,
            "PumpManagerState": {"managerIdentifier": "TandemPumpManager", "state": {}},
        }.items():
            write_plist(documents / f"{key}.plist", value)
        return {}


class Loop:
    """Loop keeps its store and onboarding state in its app group (com.loopkit.LoopKit/Model.sqlite, the
    suite named by AppGroupIdentifier); the test adds its therapy settings, as the legacy keys Loop migrates."""

    name = "Loop"
    stores = [("group", "Model.sqlite*")]
    logs = ["Documents/tandem", "Documents/DeviceLog"]
    fresh_group_container = True

    @staticmethod
    def seed(data, group, info):
        write_plist(Path(data) / "Documents" / "PumpManagerState.plist",
                    {"managerIdentifier": "TandemPumpManager", "state": {}})
        return {"com.loopkit.Loop.OnboardingManager.IsComplete": True}


HOSTS = {"trio": Trio, "loop": Loop}


def resolve_udid(udid):
    if udid != "booted":
        return udid
    devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"], check=True,
                                        capture_output=True, text=True).stdout)["devices"]
    booted = [d["udid"] for runtime in devices.values() for d in runtime if d.get("state") == "Booted"]
    if not booted:
        raise SystemExit("no booted simulator; boot one or pass --udid")
    return booted[0]


class App:
    def __init__(self, host, udid, app, gatt, log_dir):
        self.host, self.udid, self.app, self.gatt = host, resolve_udid(udid), Path(app), gatt
        self.info = plistlib.loads((self.app / "Info.plist").read_bytes())
        self.bundle_id = self.info["CFBundleIdentifier"]
        self.group_id = self.info.get("AppGroupIdentifier")
        self.log_dir = Path(log_dir)
        self.container = None
        self.group = None
        self.name = None
        self.arguments = []
        self.running = False
        self.pid = None

    def simctl(self, *args, check=True):
        return subprocess.run(["xcrun", "simctl", *args], check=check, capture_output=True, text=True)

    def group_container(self):
        out = self.simctl("get_app_container", self.udid, self.bundle_id, "groups", check=False).stdout
        groups = dict(line.split(None, 1) for line in out.splitlines() if len(line.split(None, 1)) == 2)
        path = groups.get(self.group_id) if self.group_id else next(iter(groups.values()), None)
        return path.strip() if path else None

    def stop(self, sample=False):
        if sample and self.running and self.pid:
            # An app that stopped answering logs nothing about why; its stacks say where it is stuck.
            path = self.archive_dir() / f"{self.host.name.lower()}-sample.txt"
            print(f"sampling {self.host.name} ({self.pid}) into {path}", flush=True)
            subprocess.run(["sample", str(self.pid), "3", "-file", str(path)], check=False, capture_output=True, timeout=120)
        self.simctl("terminate", self.udid, self.bundle_id, check=False)
        if self.running and self.container:
            self.archive()
        self.running = False
        self.pid = None

    def archive_dir(self):
        target = self.log_dir / re.sub(r"[^A-Za-z0-9._-]+", "_", self.name or self.host.name).strip("_-")
        target.mkdir(parents=True, exist_ok=True)
        return target

    def archive(self):
        """Simulated data only: what a failed test's artifacts need."""
        target = self.archive_dir()
        for rel in self.host.logs:
            source = Path(self.container) / rel
            if source.is_dir():
                shutil.copytree(source, target / rel.replace("/", "-").lower(), dirs_exist_ok=True)
        for where, pattern in self.host.stores:
            root = self.container if where == "data" else self.group
            for store in Path(root).rglob(pattern) if root else []:
                shutil.copy2(store, target)

    def empty_group_containers(self):
        """The simulator keeps an app group container across reinstalls, with the last test's store and
        UserDefaults in it. The container's metadata stays, so it stays registered."""
        out = self.simctl("get_app_container", self.udid, self.bundle_id, "groups", check=False).stdout
        for line in out.splitlines():
            parts = line.split(None, 1)
            path = Path(parts[1].strip()) if len(parts) == 2 else None
            if not path or not path.is_dir():
                continue
            for child in path.iterdir():
                if child.name == CONTAINER_METADATA:
                    continue
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child, ignore_errors=True)
                else:
                    child.unlink(missing_ok=True)

    def drop_preferences_cache(self):
        """cfprefsd answers UserDefaults from memory, not from a plist written behind its back. The device's
        launchd_sim restarts its instances on demand, and they read the files again."""
        sim = subprocess.run(["pgrep", "-f", f"launchd_sim.*{self.udid}"], capture_output=True, text=True).stdout.split()
        killed = []
        for parent in sim:
            for pid in subprocess.run(["pgrep", "-P", parent, "cfprefsd"], capture_output=True, text=True).stdout.split():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                    killed.append(pid)
                except (ProcessLookupError, ValueError):
                    pass
        print(f"restarted the simulator's cfprefsd ({', '.join(killed)})" if killed else
              f"found no cfprefsd under launchd_sim for {self.udid}: the seeded UserDefaults may not be read", flush=True)

    def install(self, name, files, defaults):
        self.stop()
        if self.host.fresh_group_container:
            self.empty_group_containers()
        self.simctl("uninstall", self.udid, self.bundle_id, check=False)
        self.simctl("install", self.udid, str(self.app))
        self.container = self.simctl("get_app_container", self.udid, self.bundle_id, "data").stdout.strip()
        self.group = self.group_container()
        self.name = name
        self.arguments = []
        if self.host.fresh_group_container and self.group:
            self.empty_group_containers()
        group_defaults = self.host.seed(self.container, self.group, self.info)
        self.write_files(files)
        group_defaults.update(self.plist_dict(defaults.get("group")))
        domains = {"app": (self.container, self.bundle_id, self.plist_dict(defaults.get("app"))),
                   "group": (self.group, self.group_id, group_defaults)}
        wrote = False
        for kind, (root, domain, values) in domains.items():
            if not values:
                continue
            if not root or not domain:
                raise RuntimeError(f"{self.bundle_id} has no {kind} container for its UserDefaults")
            write_plist(Path(root) / "Library" / "Preferences" / f"{domain}.plist", values)
            wrote = True
        if wrote:
            self.drop_preferences_cache()
        return {"dataContainer": self.container, "groupContainer": self.group or ""}

    @staticmethod
    def plist_dict(text):
        if not text:
            return {}
        value = plistlib.loads(text.encode())
        if not isinstance(value, dict):
            raise ValueError("defaults must be a plist dictionary")
        return value

    def write_files(self, files):
        for relative, text in files.items():
            group = relative.startswith("group:")
            root_path = self.group if group else self.container
            if not root_path:
                raise RuntimeError(f"{self.bundle_id} has no app group container for {relative}")
            root = Path(root_path).resolve()
            path = (root / relative.removeprefix("group:")).resolve()
            if root not in path.parents:
                raise ValueError(f"{relative} is outside the container")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def launch(self, arguments):
        if not self.container:
            raise RuntimeError(f"no {self.host.name} installed; POST /install first")
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
        return {"controlPort": port, "dataContainer": self.container, "groupContainer": self.group or ""}


def serve(app, port_file):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            try:
                length = int(self.headers.get("Content-Length") or 0)
                request = json.loads(self.rfile.read(length) or b"{}")
                if url.path == "/install":
                    body = app.install(query.get("name", [app.host.name])[0], request.get("files", {}), request.get("defaults", {}))
                elif url.path == "/launch":
                    body = app.launch(request.get("arguments", []))
                elif url.path == "/relaunch":
                    body = app.launch(app.arguments)
                elif url.path == "/stop":
                    app.stop(sample=bool(request.get("sample")))
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
        app.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shut_down)
    signal.signal(signal.SIGINT, shut_down)
    Path(port_file).write_text(str(server.server_address[1]))
    server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", choices=sorted(HOSTS), required=True, help="which app: its seed, store and logs")
    parser.add_argument("--udid", required=True)
    parser.add_argument("--app", required=True, help="the built .app")
    parser.add_argument("--gatt", required=True, help="faketandem's virtual GATT address, host:port")
    parser.add_argument("--log-dir", required=True)
    parser.add_argument("--port-file", required=True, help="written with the port once listening")
    args = parser.parse_args()
    serve(App(HOSTS[args.host], args.udid, args.app, args.gatt, args.log_dir), args.port_file)


if __name__ == "__main__":
    main()
