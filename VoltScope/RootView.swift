import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum VSStyle {
    static let background = Color(red: 0.045, green: 0.060, blue: 0.095)
    static let card = Color(red: 0.095, green: 0.120, blue: 0.170)
    static let cyan = Color(red: 0.29, green: 0.91, blue: 0.92)
    static let green = Color(red: 0.50, green: 0.97, blue: 0.62)
    static let secondary = Color(red: 0.63, green: 0.69, blue: 0.76)
}

private struct Panel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VSStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

private struct SectionHeading: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(VSStyle.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = VSStyle.cyan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0).foregroundStyle(VSStyle.secondary)
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7).lineLimit(1).foregroundStyle(tint)
            Text(detail).font(.system(size: 11)).foregroundStyle(VSStyle.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(VSStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PercentageRing: View {
    let percentage: Double
    let charging: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 17)
            Circle().trim(from: 0, to: min(1, max(0, percentage / 100)))
                .stroke(AngularGradient(colors: charging ? [VSStyle.green, VSStyle.cyan] : [VSStyle.cyan, .blue], center: .center),
                        style: StrokeStyle(lineWidth: 17, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: charging ? "bolt.fill" : "battery.100percent")
                    .font(.title2).foregroundStyle(charging ? VSStyle.green : VSStyle.cyan)
                Text("\(Int(percentage.rounded()))%")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(charging ? "CHARGING" : "BATTERY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.2).foregroundStyle(VSStyle.secondary)
            }
        }
        .frame(width: 210, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Int(percentage.rounded())) percent, \(charging ? "charging" : "not charging")")
    }
}

struct RootView: View {
    @EnvironmentObject private var service: BatteryService
    @State private var selected = 0
    @State private var showsSettings = false

    var body: some View {
        TabView(selection: $selected) {
            NavigationStack { DashboardView() }.tabItem { Label("Overview", systemImage: "battery.100percent") }.tag(0)
            NavigationStack { ChargingView() }.tabItem { Label("Charging", systemImage: "bolt.circle") }.tag(1)
            NavigationStack { DevicesView() }.tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }.tag(2)
            NavigationStack { InsightsView() }.tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }.tag(3)
        }
        .tint(VSStyle.cyan)
        .background(VSStyle.background)
        .toolbarBackground(VSStyle.background, for: .tabBar)
        .sheet(isPresented: $showsSettings) { SettingsView().environmentObject(service) }
        .onReceive(NotificationCenter.default.publisher(for: .init("VoltScope.showSettings"))) { _ in
            showsSettings = true
        }
    }
}

private struct TopTitle: View {
    let caption: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("VOLTSCOPE").font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3.5).foregroundStyle(VSStyle.cyan)
                Text(caption).font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Spacer()
            Button {
                NotificationCenter.default.post(name: .init("VoltScope.showSettings"), object: nil)
            } label: {
                Image(systemName: "gearshape.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(VSStyle.card, in: Circle())
            }.accessibilityLabel("Settings")
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var service: BatteryService
    private var latest: BatterySample? { service.latest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TopTitle(caption: "Battery overview")
                Panel {
                    VStack(spacing: 18) {
                        PercentageRing(percentage: latest?.percentage ?? 0, charging: latest?.isCharging ?? false)
                        HStack(spacing: 7) {
                            Circle().fill(latest?.isCharging == true ? VSStyle.green : VSStyle.cyan)
                                .frame(width: 7, height: 7)
                            Text(latest?.state ?? "Waiting for reading")
                                .font(.subheadline.weight(.medium))
                            Text("•")
                            Text(UIDevice.current.model).foregroundStyle(VSStyle.secondary)
                        }.font(.caption)
                        if let hours = service.remainingHours {
                            Text("~\(hours.formatted(.number.precision(.fractionLength(1)))) h estimated remaining")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(VSStyle.cyan)
                        } else if let hours = service.chargeHoursToFull {
                            Text("~\(hours.formatted(.number.precision(.fractionLength(1)))) h linear charge estimate")
                                .font(.caption).foregroundStyle(VSStyle.green)
                        } else {
                            Text("Monitoring to establish an accurate trend")
                                .font(.caption).foregroundStyle(VSStyle.secondary)
                        }
                    }.frame(maxWidth: .infinity)
                }
                HStack(spacing: 10) {
                    MetricTile(title: "Discharge", value: formatRate(service.trend(charging: false)),
                               detail: "Observed % per hour", tint: .orange)
                    MetricTile(title: "Thermal", value: latest?.thermalState ?? "—",
                               detail: "System pressure", tint: VSStyle.green)
                    MetricTile(title: "Health", value: healthText(latest),
                               detail: "Hardware if available")
                }
                SectionHeading(title: "Battery timeline", subtitle: "Locally recorded levels • up to 14 days")
                Panel { BatteryHistoryChart(samples: service.samples) }
                SectionHeading(title: "Connected batteries")
                Panel {
                    if service.accessories.isEmpty {
                        Label("No accessory readings yet. Scan from Devices or connect FindMyBLE.",
                              systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline).foregroundStyle(VSStyle.secondary)
                    } else {
                        ForEach(Array(service.accessories.prefix(4))) { item in
                            AccessoryRow(item: item, showButton: false)
                            if item.id != service.accessories.prefix(4).last?.id {
                                Divider().overlay(.white.opacity(0.1))
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: service.hasDiagnostics ? "checkmark.shield.fill" : "lock.shield")
                    Text(service.hasDiagnostics
                         ? "Device sensor readings available. Values refresh while VoltScope is open."
                         : "Private sensors unavailable on this device. Battery levels and trends still work.")
                }.font(.caption).foregroundStyle(VSStyle.secondary).padding(.horizontal, 4)
            }
            .padding(18)
        }
        .background(VSStyle.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .refreshable { service.refresh() }
    }
}

private struct BatteryHistoryChart: View {
    let samples: [BatterySample]
    var body: some View {
        let recent = samples.filter { $0.date >= Date().addingTimeInterval(-24 * 3600) }
        if recent.count < 2 {
            VStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(VSStyle.cyan)
                Text("Your 24-hour history builds as VoltScope observes the battery.")
                    .font(.caption).foregroundStyle(VSStyle.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 160)
        } else {
            Chart(recent) { reading in
                AreaMark(x: .value("Time", reading.date), yStart: .value("Base", 0),
                         yEnd: .value("Charge", reading.percentage))
                    .foregroundStyle(VSStyle.cyan.opacity(0.08))
                LineMark(x: .value("Time", reading.date), y: .value("Charge", reading.percentage))
                    .interpolationMethod(.linear).foregroundStyle(VSStyle.cyan).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
            .frame(height: 180)
        }
    }
}

private struct ChargingView: View {
    @EnvironmentObject private var service: BatteryService
    private var s: BatterySample? { service.latest }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TopTitle(caption: "Charging lab")
                Panel {
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 54)).foregroundStyle(s?.isCharging == true ? VSStyle.green : VSStyle.cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(s?.state ?? "Unknown").font(.title2.bold())
                            Text("Live electrical measurements are shown only when available from the hardware.")
                                .font(.caption).foregroundStyle(VSStyle.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    MetricTile(title: "Cell current", value: format(s?.currentMA, unit: "mA", digits: 0),
                               detail: "Measured while charging, not discharge")
                    MetricTile(title: "Voltage", value: format(s?.voltageMV, unit: "mV", digits: 0),
                               detail: "Cell voltage")
                }
                HStack(spacing: 10) {
                    MetricTile(title: "Pack power", value: format(s?.watts, unit: "W", digits: 2),
                               detail: "Measured power into battery", tint: VSStyle.green)
                    MetricTile(title: "Temperature", value: format(s?.temperatureC, unit: "°C", digits: 1),
                               detail: "Battery sensor if exposed", tint: .orange)
                }
                SectionHeading(title: "USB-C input", subtitle: "Measured separately from power reaching the battery")
                HStack(spacing: 10) {
                    MetricTile(title: "From charger", value: format(s?.usbInputWatts, unit: "W", digits: 2),
                               detail: "Actual input if complete", tint: VSStyle.green)
                    MetricTile(title: "Port voltage", value: format(s?.usbInputVoltageMV, unit: "mV", digits: 0),
                               detail: "USB rail, not cell")
                    MetricTile(title: "Port current", value: format(s?.usbInputCurrentMA, unit: "mA", digits: 0),
                               detail: "USB rail, not cell")
                }
                if let keys = s?.sensorKeys, !keys.isEmpty {
                    Panel {
                        Label("On-device sensors active", systemImage: "waveform.path.ecg")
                            .font(.subheadline.bold()).foregroundStyle(VSStyle.green)
                        Text("\(s?.sensorCount ?? 0) endpoints • keys: \(keys.joined(separator: ", "))")
                            .font(.caption2.monospaced()).foregroundStyle(VSStyle.secondary)
                            .textSelection(.enabled)
                        Text("Readings are device dependent. iOS may hide some sensors or publish only a partial USB input path.")
                            .font(.caption).foregroundStyle(VSStyle.secondary)
                    }
                }
                SectionHeading(title: "Battery condition")
                Panel {
                    VStack(spacing: 15) {
                        ValueLine(label: "Cycle count", value: s?.cycleCount.map(String.init) ?? "Unavailable")
                        ValueLine(label: "Design capacity", value: format(s?.designCapacityMAh, unit: "mAh", digits: 0))
                        ValueLine(label: "Maximum capacity", value: format(s?.maximumCapacityMAh, unit: "mAh", digits: 0))
                        ValueLine(label: "Remaining capacity", value: format(s?.remainingCapacityMAh, unit: "mAh", digits: 0))
                        ValueLine(label: "Estimated health", value: healthText(s))
                        ValueLine(label: "Low Power Mode", value: s?.lowPowerMode == true ? "On" : "Off")
                    }
                }
                SectionHeading(title: "Charging pace")
                Panel {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(formatRate(service.trend(charging: true)))
                            .font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(VSStyle.green)
                        Text("% per hour, estimated from observed charging samples. A full-charge ETA is approximate because charging tapers near 80–100%.")
                            .font(.caption).foregroundStyle(VSStyle.secondary)
                    }
                }
                if !service.hasDiagnostics {
                    Panel {
                        Label("iOS sensor restrictions", systemImage: "info.circle.fill")
                            .font(.headline).foregroundStyle(VSStyle.cyan)
                        Text("VoltScope probes read-only private HID power sensors and the IOKit battery registry. Private APIs are device-specific and can stop working after an update. Cycle count, health and discharge current remain unavailable without additional privileges. Missing or partial data stays blank.")
                            .font(.subheadline).foregroundStyle(VSStyle.secondary)
                    }
                }
            }.padding(18)
        }
        .background(VSStyle.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

private struct DevicesView: View {
    @EnvironmentObject private var service: BatteryService
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TopTitle(caption: "Device batteries")
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.title2).foregroundStyle(VSStyle.cyan)
                            VStack(alignment: .leading) {
                                Text("Bluetooth scan").font(.headline)
                                Text("18 seconds • runs only when requested")
                                    .font(.caption).foregroundStyle(VSStyle.secondary)
                            }
                            Spacer()
                            Button(service.scanning ? "Stop" : "Scan") {
                                service.scanning ? service.stopScan() : service.scanDevices()
                            }
                            .buttonStyle(.borderedProminent).tint(VSStyle.cyan)
                            .foregroundStyle(.black)
                        }
                        if let message = service.bluetoothMessage {
                            Text(message).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FindMyBLE integration").font(.headline)
                            Text(service.findMyBLEAccessible ? "Automatic shared cache available" : "Shared cache blocked by signing")
                                .font(.caption).foregroundStyle(service.findMyBLEAccessible ? VSStyle.green : VSStyle.secondary)
                            Text("Fetch LARQ and supported Apple device percentages from your FindMyBLE tracker.")
                                .font(.caption).foregroundStyle(VSStyle.secondary)
                        }
                        Spacer()
                        Button { service.syncFindMyBLE() } label: {
                            Image(systemName: "arrow.clockwise").font(.title3)
                        }.accessibilityLabel("Refresh FindMyBLE")
                    }
                    Button {
                        if let url = URL(string: "findmyble://battery-export") { openURL(url) }
                    } label: {
                        Label("Fetch from FindMyBLE", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VSStyle.cyan)
                    .foregroundStyle(.black)
                    Text("Opens FindMyBLE and returns to VoltScope with battery data. Works without App Groups after both apps are updated.")
                        .font(.caption2).foregroundStyle(VSStyle.secondary)
                    if let date = service.lastFindMySync {
                        Text("Last transfer: \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(VSStyle.green)
                    }
                    }
                }
                SectionHeading(title: "Discovered and tracked", subtitle: "Only compatible devices expose a readable battery level")
                if service.accessories.isEmpty {
                    Panel {
                        VStack(spacing: 12) {
                            Image(systemName: "battery.0percent").font(.largeTitle)
                                .foregroundStyle(VSStyle.cyan)
                            Text("No compatible devices yet").font(.headline)
                            Text("Scan nearby Bluetooth devices, or ensure FindMyBLE has a cached LARQ reading.")
                                .font(.caption).foregroundStyle(VSStyle.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    }
                } else {
                    ForEach(service.accessories) { device in
                        Panel { AccessoryRow(item: device, showButton: device.source == .bluetooth) }
                    }
                }
                Text("Find My may report battery for selected Apple devices. It does not always report AirPods case or separate left/right earbud levels. Unknown percentages remain blank.")
                    .font(.caption).foregroundStyle(VSStyle.secondary).padding(.horizontal, 4)
            }.padding(18)
        }
        .background(VSStyle.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear { service.syncFindMyBLE() }
    }
}

private struct AccessoryRow: View {
    @EnvironmentObject private var service: BatteryService
    let item: AccessoryBattery
    let showButton: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .font(.title2).foregroundStyle(VSStyle.cyan)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.bold()).lineLimit(1)
                Text("\(item.source.rawValue) • \(item.connected ? "Connected" : "Last seen")")
                    .font(.caption).foregroundStyle(VSStyle.secondary)
                if let note = item.note { Text(note).font(.caption2).foregroundStyle(VSStyle.secondary).lineLimit(2) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.percentage.map { "\($0)%" } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(item.percentage.map { $0 <= 20 ? Color.orange : VSStyle.green } ?? VSStyle.secondary)
                if item.percentage != nil {
                    Text(item.isStale ? "Older reading" : "Recent")
                        .font(.system(size: 10)).foregroundStyle(VSStyle.secondary)
                }
                if showButton {
                    Button(item.connected ? "Disconnect" : "Read battery") {
                        item.connected ? service.disconnectDevice(item.id) : service.connectDevice(item.id)
                    }.font(.caption.bold()).buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct InsightsView: View {
    @EnvironmentObject private var service: BatteryService
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TopTitle(caption: "Energy insights")
                Panel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: service.highDrain ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                            .foregroundStyle(service.highDrain ? .orange : VSStyle.cyan).font(.title)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(service.highDrain ? "Elevated drain observed" : "Discharge trend")
                                .font(.headline)
                            Text(formatRate(service.trend(charging: false)))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(service.highDrain
                                 ? "Sustained drain is above 12% per hour in the observed period. Check Settings → Battery to identify the contributing apps."
                                 : "A 12-minute observation window is required before a discharge rate can be estimated.")
                                .font(.caption).foregroundStyle(VSStyle.secondary)
                        }
                    }
                }
                SectionHeading(title: "What can affect drain")
                Panel {
                    VStack(alignment: .leading, spacing: 15) {
                        InsightLine(icon: "thermometer.medium", title: "Thermal pressure",
                                    value: service.latest?.thermalState ?? "Unknown",
                                    detail: "iOS may reduce performance when the device gets warm")
                        Divider().overlay(.white.opacity(0.1))
                        InsightLine(icon: "battery.25percent", title: "Low Power Mode",
                                    value: service.latest?.lowPowerMode == true ? "Enabled" : "Disabled",
                                    detail: "Reduces some background work and visual effects")
                        Divider().overlay(.white.opacity(0.1))
                        InsightLine(icon: "chart.line.downtrend.xyaxis", title: "Observed battery drain",
                                    value: formatRate(service.trend(charging: false)),
                                    detail: "A trend, not attribution to a particular app")
                    }
                }
                SectionHeading(title: "Daily observed discharge", subtitle: "Only while VoltScope was allowed to sample")
                Panel {
                    if service.dailyDrainSummary().isEmpty {
                        Text("Discharge history will appear after multiple observations.")
                            .font(.subheadline).foregroundStyle(VSStyle.secondary)
                    } else {
                        ForEach(service.dailyDrainSummary().prefix(7)) { item in
                            HStack {
                                Text(item.id.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(Int(item.percentage.rounded()))% observed")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(VSStyle.cyan)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Panel { PowerLogInspectorView() }
                Panel {
                    DisclosureGroup("Optional screenshot comparison") {
                        BatteryDetectiveView()
                            .padding(.top, 12)
                    }
                }
            }.padding(18)
        }
        .background(VSStyle.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

private struct InsightLine: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(VSStyle.cyan)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.subheadline.bold())
                    Spacer()
                    Text(value).font(.caption.weight(.bold)).foregroundStyle(VSStyle.green)
                }
                Text(detail).font(.caption).foregroundStyle(VSStyle.secondary)
            }
        }
    }
}

private struct ValueLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(VSStyle.secondary)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }
}

private func format(_ number: Double?, unit: String, digits: Int) -> String {
    guard let number, number.isFinite else { return "Unavailable" }
    return "\(number.formatted(.number.precision(.fractionLength(digits)))) \(unit)"
}

private func healthText(_ reading: BatterySample?) -> String {
    guard let health = reading?.healthPercentage, (20...120).contains(health) else { return "—" }
    return "\(Int(health.rounded()))%"
}

private func formatRate(_ trend: BatteryTrend?) -> String {
    guard let trend else { return "—" }
    return String(format: "%+.1f%%/h", trend.percentagePerHour)
}

struct BatteryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(samples: [BatterySample]) {
        var rows = ["timestamp,percentage,state,thermal_state,low_power,voltage_mV,current_mA,temperature_C,cycle_count,design_mAh,max_mAh,source"]
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        for sample in samples {
            let fields: [String] = [
                ISO8601DateFormatter().string(from: sample.date),
                String(sample.percentage), sample.state, sample.thermalState,
                String(sample.lowPowerMode), number(sample.voltageMV),
                number(sample.currentMA), number(sample.temperatureC),
                sample.cycleCount.map { String($0) } ?? "", number(sample.designCapacityMAh),
                number(sample.maximumCapacityMAh), sample.source.rawValue
            ]
            rows.append(fields.joined(separator: ","))
        }
        text = rows.joined(separator: "\n") + "\n"
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var service: BatteryService
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var exportDocument: BatteryCSVDocument?

    var body: some View {
        NavigationStack {
            Form {
                Section("Availability") {
                    LabeledContent("Hardware readings", value: service.hasDiagnostics ? "Available" : "Restricted")
                    LabeledContent("Widget data sharing", value: service.widgetShared ? "Ready" : "Signing required")
                    LabeledContent("FindMyBLE sharing", value: service.findMyBLEAccessible ? "Ready" : "Unavailable")
                    LabeledContent("History samples", value: "\(service.samples.count)")
                }
                Section("Your data") {
                    Button {
                        exportDocument = BatteryCSVDocument(samples: service.samples)
                        exporting = true
                    } label: {
                        Label("Export battery history as CSV", systemImage: "square.and.arrow.up")
                    }
                    Text("Export uses the native iOS Files picker. Readings stay on this phone unless you export them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diagnostic notes") {
                    Text("Battery sampling occurs while the app is active or iOS wakes it. Widget updates are scheduled by iOS and are not live meters.")
                    Text("Charging current is battery-pack current, not the charger's wall-input power. Its sign can differ by battery controller.")
                    Text("Only accessories exposing a readable BLE battery service, or entries accessible from FindMyBLE's cache, can report percentages.")
                }.font(.footnote)
                Section("Installed build") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: exportDocument,
                          contentType: .commaSeparatedText, defaultFilename: "VoltScope-Battery-History") { _ in }
        }
        .preferredColorScheme(.dark)
    }
}
