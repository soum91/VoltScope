import WidgetKit
import SwiftUI

private enum WidgetPalette {
    static let base = Color(red: 0.065, green: 0.085, blue: 0.130)
    static let cyan = Color(red: 0.29, green: 0.91, blue: 0.92)
    static let green = Color(red: 0.50, green: 0.97, blue: 0.62)
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
                  devices: [AccessoryBattery(id: "preview", name: "LARQ Bottle", percentage: 81,
                                             connected: true, updated: .now, source: .findMyBLE)],
                  observedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoltEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func read() -> VoltEntry {
        let archive = SharedBatteryStore.read()
        return VoltEntry(date: .now, phone: archive.samples.last,
                         devices: archive.accessories, observedAt: archive.lastSaved)
    }
}

private struct BatteryArc: View {
    let level: Double
    let charging: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 7)
            Circle().trim(from: 0, to: max(0, min(level / 100, 1)))
                .stroke(charging ? WidgetPalette.green : WidgetPalette.cyan,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(level.rounded()))%")
                .font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
        }
    }
}

struct PhoneWidgetView: View {
    var entry: VoltEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 16) {
                    BatteryArc(level: entry.phone?.percentage ?? 0,
                               charging: entry.phone?.isCharging == true)
                        .frame(width: 105, height: 105)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOLTSCOPE").font(.caption2.bold()).tracking(2)
                            .foregroundStyle(WidgetPalette.cyan)
                        Label(entry.phone?.state ?? "Waiting", systemImage: "bolt.fill")
                            .font(.subheadline.bold())
                        Text(entry.phone?.thermalState ?? "No thermal reading")
                            .font(.caption).foregroundStyle(.secondary)
                        if let date = entry.phone?.date {
                            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let device = entry.devices.first(where: { $0.percentage != nil }) {
                            Divider()
                            HStack {
                                Text(device.name).lineLimit(1)
                                Spacer(minLength: 5)
                                Text("\(device.percentage ?? 0)%").bold()
                            }.font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(16)
            } else {
                VStack(spacing: 9) {
                    HStack {
                        Text("VOLTSCOPE").font(.caption2.bold()).tracking(1.7)
                        Spacer()
                        Image(systemName: entry.phone?.isCharging == true ? "bolt.fill" : "battery.100percent")
                    }.foregroundStyle(WidgetPalette.cyan)
                    Spacer(minLength: 0)
                    BatteryArc(level: entry.phone?.percentage ?? 0, charging: entry.phone?.isCharging == true)
                        .frame(width: 98, height: 98)
                    Spacer(minLength: 0)
                    if let date = entry.phone?.date {
                        Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No reading").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(14)
            }
        }
        .background(WidgetPalette.base)
        .widgetURL(URL(string: "voltscope://overview"))
    }
}

struct DeviceWidgetView: View {
    var entry: VoltEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("DEVICE BATTERIES").font(.caption2.bold()).tracking(1.5)
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
            }.foregroundStyle(WidgetPalette.cyan)
            if entry.devices.isEmpty {
                Spacer()
                Text("Connect a BLE device or share FindMyBLE readings")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.devices.prefix(3))) { device in
                    HStack {
                        Circle().fill(device.connected ? WidgetPalette.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(device.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(device.percentage.map { "\($0)%" } ?? "—")
                            .fontWeight(.bold).foregroundStyle(device.isStale ? .secondary : .primary)
                    }.font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            Text("Last recorded • not live")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(WidgetPalette.base)
        .widgetURL(URL(string: "voltscope://devices"))
    }
}

struct LockBatteryView: View {
    let entry: VoltEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: entry.phone?.percentage ?? 0, in: 0...100) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                Text("\(Int((entry.phone?.percentage ?? 0).rounded()))")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        }.widgetURL(URL(string: "voltscope://overview"))
    }
}

struct VoltPhoneWidget: Widget {
    let kind = "VoltScope.phone"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { PhoneWidgetView(entry: $0) }
            .configurationDisplayName("iPhone Battery")
            .description("Recorded iPhone battery level, charging status and temperature pressure.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VoltDevicesWidget: Widget {
    let kind = "VoltScope.devices"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { DeviceWidgetView(entry: $0) }
            .configurationDisplayName("Accessory Batteries")
            .description("LARQ via FindMyBLE and standard Bluetooth battery devices.")
            .supportedFamilies([.systemMedium])
    }
}

struct VoltLockWidget: Widget {
    let kind = "VoltScope.lock"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltProvider()) { LockBatteryView(entry: $0) }
            .configurationDisplayName("Battery Lock Screen")
            .description("A compact recorded battery indicator for the Lock Screen.")
            .supportedFamilies([.accessoryCircular])
    }
}

@main
struct VoltScopeWidgets: WidgetBundle {
    var body: some Widget {
        VoltPhoneWidget()
        VoltDevicesWidget()
        VoltLockWidget()
    }
}
