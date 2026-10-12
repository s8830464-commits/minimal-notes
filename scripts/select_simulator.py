#!/usr/bin/env python3
"""Select or create an iPhone simulator for the exact requested iOS runtime."""
import json
import os
import subprocess
import sys


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


expected = os.environ.get("EXPECTED_IOS_SDK", "27.2")
runtimes = json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
runtime = next((item for item in runtimes
                if item.get("isAvailable") and item.get("version", "").split(".")[:2]
                == expected.split(".")[:2] and ".iOS-" in item["identifier"]), None)
if runtime is None:
    sys.exit(f"No available iOS {expected} runtime. Install it in Xcode.")
runtime_id = runtime["identifier"]
devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
for device in devices.get(runtime_id, []):
    if device.get("isAvailable") and device["name"].startswith("iPhone"):
        print(device["udid"])
        sys.exit(0)

types = runtime.get("supportedDeviceTypes")
if types is None:
    types = json.loads(simctl("list", "devicetypes", "--json"))["devicetypes"]
parts = [int(value) for value in expected.split(".")]
runtime_version = (parts[0] << 16) | (parts[1] << 8)
candidates = [item for item in types
              if item["name"].startswith("iPhone")
              and item.get("minRuntimeVersion", 0) <= runtime_version
              and item.get("maxRuntimeVersion", 0xFFFFFFFF) >= runtime_version]
if not candidates:
    sys.exit(f"No supported iPhone device type for iOS {expected}")
print(simctl("create", "NotesApp-Tests", candidates[-1]["identifier"], runtime_id))
