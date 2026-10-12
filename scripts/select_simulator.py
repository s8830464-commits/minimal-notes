#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator for the requested iOS."""
import json
import os
import subprocess
import sys

expected = os.environ.get("EXPECTED_IOS_SDK", "27.2")
payload = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
runtime_suffix = ".iOS-" + expected.replace(".", "-")
for runtime, devices in payload["devices"].items():
    if runtime.endswith(runtime_suffix) or runtime.endswith(runtime_suffix + "-0"):
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                print(device["udid"])
                sys.exit(0)
sys.exit(f"No available iPhone simulator with iOS {expected}. Install that runtime in Xcode.")
