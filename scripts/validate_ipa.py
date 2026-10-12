#!/usr/bin/env python3
"""Read-only validation of the unsigned NotesApp distribution archive."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import struct
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(value):
    return f"{value >> 16}.{(value >> 8) & 255}.{value & 255}"


def validate(path, expected_sdk=None, require_metadata=False):
    path = pathlib.Path(path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        require(all(not name.startswith("/") and ".." not in pathlib.PurePosixPath(name).parts
                    and "\\" not in name for name in names), "Unsafe archive path")
        require(archive.testzip() is None, "ZIP checksum failed")
        plist_path = "Payload/NotesApp.app/Info.plist"
        require(plist_path in names, "Expected app bundle is missing")
        info = plistlib.loads(archive.read(plist_path))
        require(info.get("CFBundleIdentifier") == "com.ivan.minimalnotes", "Unexpected bundle ID")
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Not an iPhoneOS app")
        require(info.get("CFBundlePackageType") == "APPL", "Not an application bundle")
        executable = info.get("CFBundleExecutable", "")
        require(executable == "NotesApp", "Unexpected executable")
        for key in ("CFBundleVersion", "CFBundleShortVersionString", "MinimumOSVersion"):
            require(isinstance(info.get(key), str) and info[key] and "$(" not in info[key],
                    f"Missing or unresolved {key}")
        if require_metadata:
            require(info.get("CFBundleDisplayName") == "Заметки", "Display name was lost")
            require(isinstance(info.get("UILaunchScreen"), dict), "Launch screen metadata was lost")
            require(isinstance(info.get("UIApplicationSceneManifest"), dict), "Scene metadata was lost")
        require(not any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision")
                        for name in names), "Expected a fresh unsigned package")
        entry = archive.getinfo("Payload/NotesApp.app/" + executable)
        require(bool((entry.external_attr >> 16) & 0o111), "Executable permission missing")
        binary = archive.read(entry)
        require(len(binary) >= 32 and binary[:4] == b"\xcf\xfa\xed\xfe",
                "Expected a 64-bit little-endian Mach-O executable")
        header = struct.unpack_from("<8I", binary)
        require(header[1] == 0x100000C and header[3] == 2, "Expected an arm64 executable")
        require(32 + header[5] <= len(binary), "Truncated load commands")
        position = 32
        platform = minimum = sdk = None
        for _ in range(header[4]):
            require(position + 8 <= 32 + header[5], "Truncated load command")
            command, size = struct.unpack_from("<II", binary, position)
            require(size >= 8 and position + size <= 32 + header[5], "Invalid load command size")
            require(command != 0x1D, "Executable already contains a signature")
            if command == 0x32:
                require(size >= 24, "Invalid build version command")
                platform, minimum, sdk, _ = struct.unpack_from("<4I", binary, position + 8)
            if command in (0x21, 0x2C):
                require(size >= 20, "Invalid encryption command")
                require(struct.unpack_from("<I", binary, position + 16)[0] == 0,
                        "Encrypted executable cannot be independently re-signed")
            position += size
        require(position == 32 + header[5], "Load command length mismatch")
        require(platform == 2, "Executable is not built for a physical iOS device")
        sdk_string = version(sdk)
        if expected_sdk:
            require(sdk_string.split(".")[:2] == expected_sdk.split(".")[:2],
                    f"Expected SDK {expected_sdk}; binary uses {sdk_string}")
        return {
            "file": path.name,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bundle_id": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"],
            "minimum_ios": version(minimum),
            "sdk": sdk_string,
            "architecture": "arm64",
            "unsigned": True,
            "requires_user_signing": True,
            "device_installation_tested": False,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--expected-sdk")
    parser.add_argument("--require-metadata", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.ipa, args.expected_sdk, args.require_metadata),
                         indent=2, ensure_ascii=False))
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        parser.exit(1, f"IPA validation failed: {error}\n")


if __name__ == "__main__":
    main()
