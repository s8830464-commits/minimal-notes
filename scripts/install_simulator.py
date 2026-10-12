#!/usr/bin/env python3
"""Install the requested iOS beta using its build ID from Apple's public catalog."""
import os
import plistlib
import subprocess
import sys
import urllib.request

expected = os.environ.get("EXPECTED_IOS_SDK", "27.2")
catalog_url = "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex"
with urllib.request.urlopen(catalog_url, timeout=60) as response:
    catalog = plistlib.loads(response.read())
candidates = [
    entry for entry in catalog.get("downloadables", [])
    if entry.get("platform") == "com.apple.platform.iphoneos"
    and entry.get("simulatorVersion", {}).get("version") == expected
    and entry.get("simulatorVersion", {}).get("buildUpdate")
    and not entry.get("isInternalContent", False)
    and entry.get("authentication", "none") == "none"
    and "arm64" in entry.get("architectures", ["arm64"])
]
if not candidates:
    sys.exit(f"Apple's public catalog has no iOS {expected} simulator for this build.")
runtime = max(candidates, key=lambda entry: tuple(int(p) for p in entry["version"].split(".")))
build = runtime["simulatorVersion"]["buildUpdate"]
print(f"Installing {runtime['name']} ({build}) from Apple", flush=True)
subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", build], check=True)
