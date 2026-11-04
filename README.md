# VoltScope

**Native iPhone battery diagnostics, history, BLE accessories, FindMyBLE integration and widgets.**

Version `0.1.0` is an unsigned native iOS build. The GitHub Actions workflow compiles an IPA on macOS, publishes a versioned GitHub release, and refreshes `repo.json` and `source.json` for FlareStore-compatible updates.

## What is implemented

- iPhone battery level, charging state, Low Power Mode and system thermal-pressure state via public iOS APIs.
- Four views: Overview, Charging Lab, Devices and Energy Insights.
- Offline 14-day recorded battery timeline, regression-based charge/discharge rates, estimated remaining time and unusual-drain warning.
- A *best-effort, optional* runtime IORegistry probe for AppleSmartBattery hardware properties on jailbroken or otherwise privileged devices: signed pack current, voltage, temperature, cycle count and capacities. All unavailable data is left blank, never faked.
- On-demand foreground Bluetooth scan (18 seconds) and Battery Service `180F` / Battery Level `2A19` discovery; cache last readings.
- **Read-only FindMyBLE integration:** reads `snapshot.json` from `group.com.soumen.findmyble` (your existing [FindMyBLE](https://github.com/soum91/FindMyBLE) stores the LARQ battery value there). No LARQ protocol reverse-engineering and no competing connection are necessary when this group is shared. If the group isn't available, use VoltScope's BLE reader to connect to the bottle directly.
- Three WidgetKit widgets: iPhone small/medium, accessory medium, and circular Lock Screen.
- Native Files picker for exporting local battery history as CSV.
- Local data only. No cloud service, advertising, analytics or credentials.

## Important iOS limits

**Stock iOS cannot supply battery pack current, voltage, cycle count, health or the system's per-app battery consumption through ordinary third-party public APIs.** The hardware probe might work on a jailbroken device with suitable privileges. A jailbreak alone does not guarantee access; sandbox entitlements and iOS versions differ. It will degrade gracefully.

Apple's own per-app percentages remain in **Settings → Battery**. VoltScope detects broad drain periods, not which other apps caused them. AirPods and Apple Watch battery percentages aren't exposed to ordinary third-party apps as a universal API. BLE devices must implement a readable standard Battery Service or be exported through FindMyBLE.

The battery timeline samples while VoltScope runs or is opportunistically awakened. iOS suspends normal apps, so background history and widgets are **not continuous, real-time sensors**. The system controls WidgetKit refresh timing.

## Build (macOS)

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open VoltScope.xcodeproj
```

Choose your own signing team under the app and widget targets. For IPA built without signing, the included GitHub Actions workflow generates a `VoltScope-unsigned-ipa` artifact **and a permanent versioned release** on pushes to `main` or manual dispatch. Both `repo.json` and `source.json` point at that release, and the build version increments with each workflow run. Sign the binary with a trusted sideloader before installing it.

FlareStore source URL (plain text):

`https://raw.githubusercontent.com/soum91/VoltScope/main/repo.json`

## FindMyBLE App Group signing

FindMyBLE publishes a JSON snapshot to `group.com.soumen.findmyble` when its monitor observes new batteries. VoltScope reads that cache only if both apps have **matching effective App Group access** after signing. If your sideloader renames/removes entitlements or signs them with different teams, sharing will not work; the Devices screen says so. VoltScope's own widget similarly requires `group.com.soumen.voltscope` on both app and extension. Some free-signing methods cannot provide App Group entitlements.

## Security and battery cost

- No hard-coded Apple ID, pairing or LARQ credentials.
- No privileged API is invoked unless opened dynamically at runtime; probe failure is safe.
- Bluetooth is scanned only by explicit request and stops after 18 seconds to avoid creating the very drain we're measuring.
- No fake per-app attribution, hidden tracking, or claims of access to Apple's private Batteries widget list.

## Next milestone

Run the unsigned build workflow, test on iPhone 17 and jailbroken iPhone 13 Pro Max, then refine the IORegistry key mappings from actual (redacted) diagnostic outputs. If the FindMyBLE App Group is unavailable after signing, add an explicit user-authorized export/deep-link bridge to FindMyBLE rather than assuming sandbox access.
