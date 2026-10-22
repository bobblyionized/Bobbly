#!/usr/bin/env python3
"""Prints the UDID of an iPhone simulator usable by the selected Xcode.

Picks the newest *available* iOS runtime whose version is <= the selected
Xcode's iPhoneSimulator SDK (compared numerically, not alphabetically),
prefers well-known iPhone models, and creates a device if the runtime has
none. Exits non-zero if nothing usable exists.
"""
import json
import subprocess
import sys

PREFERRED = ["iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro", "iPhone 17", "iPhone 17 Pro"]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def version_tuple(text):
    parts = []
    for piece in str(text).split("."):
        digits = "".join(ch for ch in piece if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def main():
    sdk = version_tuple(run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"))
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"]
    ios = [r for r in runtimes
           if r.get("isAvailable", False) and (r.get("platform") == "iOS" or "iOS" in r.get("name", ""))]
    if not ios:
        sys.exit("no available iOS simulator runtime")

    compatible = [r for r in ios if version_tuple(r["version"])[:2] <= sdk[:2]] or ios
    runtime = max(compatible, key=lambda r: version_tuple(r["version"]))
    print(f"SDK {'.'.join(map(str, sdk))} -> runtime {runtime['identifier']} ({runtime['version']})", file=sys.stderr)

    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
    iphones = [d for d in devices.get(runtime["identifier"], []) if d["name"].startswith("iPhone")]
    for name in PREFERRED:
        for device in iphones:
            if device["name"] == name:
                print(device["udid"])
                return
    if iphones:
        print(iphones[0]["udid"])
        return

    # No device for this runtime yet: create one.
    types = runtime.get("supportedDeviceTypes") or json.loads(run("xcrun", "simctl", "list", "devicetypes", "-j"))["devicetypes"]
    iphone_types = [t for t in types if t.get("name", "").startswith("iPhone")]
    if not iphone_types:
        sys.exit("no iPhone device type for runtime")
    chosen = next((t for name in PREFERRED for t in iphone_types if t["name"] == name), iphone_types[-1])
    udid = run("xcrun", "simctl", "create", "Bobbly CI iPhone", chosen["identifier"], runtime["identifier"])
    print(f"created {chosen['name']} {udid}", file=sys.stderr)
    print(udid)


if __name__ == "__main__":
    main()
