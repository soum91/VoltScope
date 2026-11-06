#!/usr/bin/env python3
"""Update the FlareStore/AltStore JSON feed after a successful IPA release.

This script runs in GitHub Actions. It intentionally has no user credentials.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: publish_feed.py path/to/VoltScope-unsigned.ipa")

    ipa_path = pathlib.Path(sys.argv[1])
    if not ipa_path.is_file():
        raise SystemExit(f"IPA not found: {ipa_path}")

    repo = os.environ.get("GITHUB_REPOSITORY", "soum91/VoltScope")
    build = os.environ.get("GITHUB_RUN_NUMBER")
    if not build or not build.isdecimal():
        raise SystemExit("GITHUB_RUN_NUMBER must be a positive decimal value")

    # Three numeric components match FlareStore's displayed/compared version.
    version = f"1.1.{build}"
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    tag = f"v{version}"
    download_url = f"https://github.com/{repo}/releases/download/{tag}/VoltScope-unsigned.ipa"
    icon_url = f"https://raw.githubusercontent.com/{repo}/main/VoltScope/Assets.xcassets/AppIcon.appiconset/VoltScope-1024.png"
    feed_url = f"https://raw.githubusercontent.com/{repo}/main/source.json"

    old_versions: list[dict] = []
    path = pathlib.Path("source.json")
    if path.exists():
        old = json.loads(path.read_text(encoding="utf-8"))
        old_apps = old.get("apps", [])
        if old_apps:
            old_versions = old_apps[0].get("versions", [])

    release = {
        "version": version,
        "buildVersion": build,
        "date": now,
        "localizedDescription": "Read-only on-device HID sensor probe for measured USB-C charging input, battery cell current and voltage, and temperature where exposed. Includes FindMyBLE handoff and device-ring widgets.",
        "changelog": "Measured USB-C input watts, current and voltage separately from battery charging power. Three-second foreground refresh, sensor-key diagnostics, device-specific icons and FindMyBLE integration. Missing and partial readings stay blank.",
        "downloadURL": download_url,
        "size": ipa_path.stat().st_size,
        "minOSVersion": "16.0",
    }
    versions = [release] + [v for v in old_versions if not (v.get("version") == version and str(v.get("buildVersion")) == build)]

    app = {
        "name": "VoltScope",
        "bundleIdentifier": "com.soumen.voltscope",
        "developerName": "soum91",
        "subtitle": "Battery diagnostics and connected-device monitoring",
        "localizedDescription": "Measured charging input and battery-side power via read-only private HID sensors when available, local history and drain trends, Bluetooth and FindMyBLE LARQ cache, and device widgets.",
        "category": "utilities",
        "iconURL": icon_url,
        "versions": versions,
        "version": version,
        "buildVersion": build,
        "versionDate": now,
        "downloadURL": download_url,
        "size": release["size"],
        "minOSVersion": "16.0",
    }
    source = {
        "name": "VoltScope",
        "identifier": "com.soumen.voltscope.source",
        "subtitle": "Battery telemetry for iPhone and compatible Bluetooth accessories",
        "description": "Unsigned native iOS builds. Sign using FlareStore or EmberSign. On-device private HID sensors may provide charging data without jailbreak; health, cycles and discharge current remain restricted.",
        "sourceURL": feed_url,
        "iconURL": icon_url,
        "apps": [app],
    }
    encoded = json.dumps(source, ensure_ascii=False, indent=2) + "\n"
    pathlib.Path("source.json").write_text(encoded, encoding="utf-8")
    pathlib.Path("repo.json").write_text(encoded, encoding="utf-8")
    print(f"Published {repo} build {build}, {release['size']} bytes")


if __name__ == "__main__":
    main()
