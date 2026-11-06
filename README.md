# VoltScope

**Native iPhone battery diagnostics, history, BLE accessories, FindMyBLE integration and widgets.**

Version `1.1.x` is an unsigned native iOS build. GitHub Actions compiles an IPA on macOS, publishes a versioned GitHub release, and refreshes `repo.json` and `source.json`. The final version component increments on every build so FlareStore detects updates. Releases before 1.1 had incorrect embedded `1.0 (1)` iOS metadata even when their JSON version changed; 1.1+ explicitly sets and verifies the version inside both the app and its widget.

## What is implemented

- iPhone battery level, charging state, Low Power Mode and system thermal-pressure state via public iOS APIs.
- Four views: Overview, Charging Lab, Devices and Energy Insights.
- Offline 14-day recorded battery timeline, regression-based charge/discharge rates, estimated remaining time and unusual-drain warning.
- A *best-effort, optional* runtime IORegistry probe for AppleSmartBattery hardware properties on jailbroken or otherwise privileged devices: signed pack current, voltage, temperature, cycle count and capacities. All unavailable data is left blank, never faked.
- **New: real charging telemetry directly on stock iOS when exposed.** A read-only private HID probe samples Apple vendor power sensors. The Charging Lab separately displays current into the battery, battery rail voltage and power, battery temperature, and complete USB-C input volts/amps/watts. The probe uses one event client per process, refreshes every three seconds while VoltScope is active, and rescans when charger connection changes. Some phone/iOS combinations hide the sensors entirely. See [third-party notices](THIRD_PARTY_NOTICES.md).
- **Battery Detective in Insights:** choose screenshots of **Settings → Battery → View All Battery Usage** using the native Photos or Files picker. Apple's Vision text recognition runs locally, extracts app names, shares and foreground/background minutes, merges overlapping screenshots without double-counting, and flags unusually long background sessions or brief high-share activity. The percentages are the system's reported usage shares, **not** independently measured watts per process. Clear the import before switching days.
- On-demand foreground Bluetooth scan (18 seconds) and Battery Service `180F` / Battery Level `2A19` discovery; cache last readings.
- **FindMyBLE integration:** reads `voltscope-batteries.json` from FindMyBLE's App Group when signing allows it. If not, tap **Fetch from FindMyBLE** in VoltScope; the updated FindMyBLE app returns a battery-only deep link. This transports LARQ's last reading plus device batteries reported by Find My without requesting the user's iCloud credentials in VoltScope.
- WidgetKit: iPhone small/medium, four-ring device medium, eight-device large, circular and rectangular Lock Screen. Icons are selected for iPhone, Watch, AirPods, charging case, LARQ bottle, and more. Unknown levels are shown as dashes, never fabricated values.
- Native Files picker for exporting local battery history as CSV.
- Local data only. No cloud service, advertising, analytics or credentials.

## Important iOS limits

**Public iOS APIs still cannot provide battery current, voltage, cycle count, health or per-app consumption.** However, research by the MiniWatts and ios-charging-monitor authors establishes that some battery-charge and USB input rails can be read through private, sandbox-accessible HID sensors on recent iPhones. VoltScope now probes those sensors, with strict value checks and labels distinguishing input power from battery-side power. There is no jailbreak or sandbox escape. Private APIs may change at any time and readings remain unavailable on unsupported hardware.

The battery charging-current endpoint `IQ0B` does **not** measure discharging current and returns zero when unplugged, so VoltScope intentionally hides it then. USB readings are hidden when an incomplete input path would incorrectly imply that the phone receives less power than the battery itself. Wireless/MagSafe has no reliably exposed measured input current on many models. Battery health and cycle count still require privileged access or external diagnostics.

Apple's own per-app percentages remain in **Settings → Battery**. Battery Detective can analyze screenshots you explicitly import, but VoltScope still cannot query other apps' power usage automatically or claim live per-app watts. AirPods and Apple Watch battery percentages aren't exposed to ordinary third-party apps as a universal API. BLE devices must implement a readable standard Battery Service or be exported through FindMyBLE.

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

FindMyBLE publishes a battery-only JSON snapshot to its group, alongside its existing widget cache. VoltScope reads it if both signed apps have matching effective App Group access. If your sideloader renames/removes entitlements or signs the apps with different teams, tap **Fetch from FindMyBLE**. That opens FindMyBLE using `findmyble://battery-export` and returns to `voltscope://import-batteries` with battery-only data. Both apps must be updated for this handoff. No locations, cookies, or Apple ID passwords are transferred. The VoltScope widget still requires a valid shared App Group between VoltScope and its own widget extension.

## Security and battery cost

- No hard-coded Apple ID, pairing or LARQ credentials.
- No privileged API is invoked unless opened dynamically at runtime; probe failure is safe.
- The private HID probe requires no entitlement or exploit, but sideloading is required; Apple does not promise that these APIs will remain available. Its three-second refresh runs only while iOS permits the app to execute. Widget refresh rates stay system-controlled.
- Bluetooth is scanned only by explicit request and stops after 18 seconds to avoid creating the very drain we're measuring.
- No fake per-app attribution, hidden tracking, or claims of access to Apple's private Batteries widget list.

## Next milestone

Run the unsigned build workflow, test on iPhone 17 and jailbroken iPhone 13 Pro Max, then refine the IORegistry key mappings from actual (redacted) diagnostic outputs. Confirm FindMyBLE's Find My feed reports each requested device before expecting a percentage: not every AirPods or Watch battery component is exposed there.
