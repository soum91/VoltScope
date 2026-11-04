import SwiftUI
import WidgetKit
import UIKit

private enum Ink {
    static let background = Color(red: 0.083, green: 0.09, blue: 0.14)
    static let lower = Color(red: 0.20, green: 0.16, blue: 0.26)
    static let cyan = Color(red: 0.43, green: 0.88, blue: 0.93)
    static let green = Color(red: 0.27, green: 0.86, blue: 0.41)
    static let orange = Color(red: 1, green: 0.72, blue: 0.22)
    static let red = Color(red: 1, green: 0.29, blue: 0.37)

    static func level(_ percentage: Int?) -> Color {
        guard let percentage else { return .gray }
        if percentage <= 20 { return red }
        if percentage <= 30 { return orange }
        return green
    }
}

struct VoltEntry: TimelineEntry {
    let date: Date
    let phone: BatterySample?
    let devices: [AccessoryBattery]
    let observedAt: Date
}

struct VoltProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoltEntry {
        VoltEntry(date: .now,
                  phone: BatterySample(percentage: 75, state: "Charging", thermalState: "Normal",
                                       lowPowerMode: false, source: .ios),
                  devices: [
                    AccessoryBattery(id: "watch", name: "Apple Watch", percentage: 15,
                                     connected: true, updated: .now, source: .findMyBLE, kind: "applewatch"),
                    AccessoryBattery(id: "pods", name: "AirPods Pro", percentage: 48,
                                     connected: true, updated: .now, source: .findMyBLE, kind: "airpodspro"),
                    AccessoryBattery(id: "larq", name: "LARQ Bottle", percentage: 61,
                                     connected: true, updated: .now, source: .findMyBLE, kind: "bottle")
                  ], observedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoltEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func read() -> VoltEntry {
        let archive = SharedBatteryStore.read()
        var phone = archive.samples.last
        // A sideloader may strip the widget's App Group entitlement. The
        // extension can still request its own device's public battery level;
        // accessory values remain unavailable until the group is restored.
        if phone == nil {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let value = UIDevice.current.batteryLevel
            if value >= 0 {
                let state: String
                switch UIDevice.current.batteryState {
                case .charging: state = "Charging"
                case .full: state = "Full"
                case .unplugged: state = "Unplugged"
                default: state = "Unknown"
                }
                phone = BatterySample(percentage: Double(value * 100), state: state,
                                      thermalState: "Unknown", lowPowerMode: false, source: .ios)
            }
        }
        return VoltEntry(date: .now, phone: phone,
                         devices: archive.accessories, observedAt: archive.lastSaved)
    }
}

private struct BatteryFace: Identifiable {
    let id: String
    let name: String
    let percentage: Int?
    let icon: String
    let charging: Bool
    let updated: Date

    init(phone: BatterySample?) {
        id = "phone"
        name = "iPhone"
        percentage = phone.map { Int($0.percentage.rounded()) }
        icon = "iphone"
        charging = phone?.isCharging == true
        updated = phone?.date ?? .distantPast
    }

    init(accessory: AccessoryBattery) {
        id = accessory.id
        name = accessory.displayName
        percentage = accessory.percentage
        icon = accessory.iconName
        charging = false
        updated = accessory.updated
    }
}

private extension VoltEntry {
    var batteries: [BatteryFace] {
        let available = devices.sorted {
            let a = ($0.percentage == nil ? 1 : 0, $0.connected ? 0 : 1, -$0.updated.timeIntervalSince1970)
            let b = ($1.percentage == nil ? 1 : 0, $1.connected ? 0 : 1, -$1.updated.timeIntervalSince1970)
            return a < b
        }
        var seen: Set<String> = []
        var distinct: [AccessoryBattery] = []
        for device in available {
            let label = device.displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(label).inserted { distinct.append(device) }
        }
        return [BatteryFace(phone: phone)] + distinct.map(BatteryFace.init(accessory:))
    }
}

private struct BottleGlyph: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 2.3)
                .frame(width: 12, height: 8).offset(y: -2)
            RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 2.4)
                .frame(width: 19, height: 30).offset(y: 3)
            Capsule().fill(.white.opacity(0.5))
                .frame(width: 2, height: 15).offset(x: -5, y: 10)
        }
        .frame(width: 36, height: 36)
    }
}

private struct BatteryRing: View {
    let face: BatteryFace
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 6)
            if let percentage = face.percentage {
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, percentage))) / 100)
                    .stroke(Ink.level(percentage),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if face.icon == "drop.fill" {
                BottleGlyph().scaleEffect(size / 80)
            } else {
                Image(systemName: face.icon)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.white)
            }
            if face.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.16, weight: .black))
                    .foregroundStyle(Ink.green)
                    .padding(4)
                    .background(Ink.background, in: Circle())
                    .offset(x: size * 0.31, y: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(face.name), \(face.percentage.map { "\($0) percent" } ?? "battery unknown")")
    }
}

private struct BatteryTile: View {
    let face: BatteryFace
    var ringSize: CGFloat = 58

    var body: some View {
        VStack(spacing: 5) {
            BatteryRing(face: face, size: ringSize)
            Text(face.percentage.map { "\($0)%" } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(face.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WidgetBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(colors: [Ink.background, Ink.lower],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            content.background(Ink.background)
        }
    }
}

struct PhoneWidgetView: View {
    let entry: VoltEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 12) {
                    BatteryRing(face: BatteryFace(phone: entry.phone), size: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("VOLTSCOPE").font(.system(size: 10, weight: .bold)).tracking(2)
                            .foregroundStyle(Ink.cyan)
                        Text(entry.phone?.percentage == nil ? "—" : "\(Int((entry.phone?.percentage ?? 0).rounded()))%")
                            .font(.system(size: 33, weight: .semibold, design: .rounded))
                        Label(entry.phone?.state ?? "No reading", systemImage: "bolt.fill")
                            .font(.caption)
                        if let first = entry.batteries.dropFirst().first, let level = first.percentage {
                            Text("\(first.name): \(level)%").font(.caption2)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let date = entry.phone?.date {
                            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(14)
            } else {
                VStack(spacing: 5) {
                    HStack {
                        Text("IPHONE").font(.system(size: 10, weight: .bold)).tracking(1.6)
                        Spacer()
                        Image(systemName: entry.phone?.isCharging == true ? "bolt.fill" : "battery.100percent")
                    }.foregroundStyle(Ink.cyan)
                    Spacer(minLength: 0)
                    BatteryRing(face: BatteryFace(phone: entry.phone), size: 78)
                    Text(entry.phone.map { "\(Int($0.percentage.rounded()))%" } ?? "—")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                }.padding(14)
            }
        }
        .modifier(WidgetBackdrop())
        .widgetURL(URL(string: "voltscope://overview"))
    }
}

struct DeviceWidgetView: View {
    let entry: VoltEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)
        let large = family == .systemLarge
        VStack(spacing: large ? 17 : 7) {
            HStack(spacing: 5) {
                Image(systemName: "battery.100percent")
                    .foregroundStyle(Ink.cyan)
                Text("BATTERIES").font(.system(size: 10, weight: .bold)).tracking(1.8)
                Spacer()
                if entry.observedAt != .distantPast {
                    Text(entry.observedAt, style: .relative)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(entry.batteries.prefix(large ? 8 : 4))) { face in
                    BatteryTile(face: face, ringSize: large ? 66 : 56)
                }
            }
            if large {
                Spacer(minLength: 0)
                Text("Battery readings update when an app or device reports them.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(large ? 19 : 13)
        .modifier(WidgetBackdrop())
        .widgetURL(URL(string: "voltscope://devices"))
    }
}

struct LockBatteryView: View {
    let entry: VoltEntry
    var body: some View {
        Gauge(value: entry.phone?.percentage ?? 0, in: 0...100) {
            Image(systemName: "iphone")
        } currentValueLabel: {
            Text(entry.phone.map { "\(Int($0.percentage.rounded()))" } ?? "—")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(URL(string: "voltscope://overview"))
    }
}

struct LockRectBatteryView: View {
    let entry: VoltEntry
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "iphone")
            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone \(entry.phone.map { "\(Int($0.percentage.rounded()))%" } ?? "—")")
                    .font(.headline)
                Text(entry.phone?.state ?? "No reading").font(.caption2)
            }
        }
        .widgetURL(URL(string: "voltscope://overview"))
    }
}

struct VoltPhoneWidget: Widget {
    let kind = "VoltScope.phone"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { PhoneWidgetView(entry: $0) }
            .configurationDisplayName("iPhone Power")
            .description("Battery percentage, charging state and last recorded reading.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VoltDevicesWidget: Widget {
    let kind = "VoltScope.devices"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { DeviceWidgetView(entry: $0) }
            .configurationDisplayName("All Batteries")
            .description("iPhone, LARQ and FindMyBLE / Find My devices, with individual icons and rings.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct VoltLockWidget: Widget {
    let kind = "VoltScope.lock"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { entry in
            LockBatteryView(entry: entry)
        }
        .configurationDisplayName("Battery Lock Screen")
        .description("A compact iPhone battery gauge.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct VoltRectWidget: Widget {
    let kind = "VoltScope.lockRect"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { entry in
            LockRectBatteryView(entry: entry)
        }
        .configurationDisplayName("Battery Status")
        .description("Battery level and charging state on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct VoltScopeWidgets: WidgetBundle {
    var body: some Widget {
        VoltPhoneWidget()
        VoltDevicesWidget()
        VoltLockWidget()
        VoltRectWidget()
    }
}
