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
    version = f"0.2.{build}"
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
        "localizedDescription": "FindMyBLE LARQ/Find My battery handoff, graceful missing App Group fallback, device-specific battery ring widgets and charging diagnostics.",
        "changelog": "LARQ and supported Apple device batteries via updated FindMyBLE. Ring widgets now show proper phone, watch, AirPods, case and bottle symbols. Three-part versioning for FlareStore.",
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
        "localizedDescription": "Charging current and voltage where device permissions allow, battery history and drain analysis, Bluetooth batteries, FindMyBLE LARQ bottle cache, and widgets.",
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
        "description": "Unsigned native iOS builds. Sign using FlareStore or EmberSign. Privileged hardware readings are best-effort on jailbroken iPhones.",
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
