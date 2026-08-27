#!/usr/bin/env python3
"""Pick an iPhone simulator on a GitHub macOS runner and export it to $GITHUB_ENV.

Writes SIMULATOR_DESTINATION (an xcodebuild -destination string) and
SIMULATOR_UDID. Prefers the newest available iOS runtime, and "iPhone 16"
within it when present, so the choice is stable across runner image bumps
without pinning a device name that may disappear.
"""

import json
import os
import re
import subprocess
import sys


def runtime_sort_key(runtime: str):
    # runtime looks like: com.apple.CoreSimulator.SimRuntime.iOS-18-6
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


def main() -> int:
    devices = json.loads(
        subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
        )
    )["devices"]

    runtimes = sorted(
        (rt for rt in devices if ".iOS-" in rt), key=runtime_sort_key, reverse=True
    )
    if not runtimes:
        sys.exit("No iOS runtimes found on runner")

    candidates = []
    for runtime in runtimes:
        candidates = [
            (device.get("name", ""), device.get("udid"), runtime)
            for device in devices.get(runtime, [])
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone")
        ]
        if candidates:
            break

    if not candidates:
        sys.exit("No available iPhone simulators found on runner")

    name, udid, runtime = next(
        (c for c in candidates if c[0] == "iPhone 16"), candidates[0]
    )
    print(f"Selected simulator: {name} ({udid}) [{runtime}]")

    with open(os.environ["GITHUB_ENV"], "a") as env_file:
        env_file.write(f"SIMULATOR_DESTINATION=platform=iOS Simulator,id={udid}\n")
        env_file.write(f"SIMULATOR_UDID={udid}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
