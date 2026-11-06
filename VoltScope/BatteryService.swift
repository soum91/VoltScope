import Foundation
import UIKit
import SwiftUI
import WidgetKit

struct BatteryTrend {
    var percentagePerHour: Double
    var duration: TimeInterval
    var points: Int
}

struct DailyDrain: Identifiable {
    var id: Date
    var percentage: Double
}

/// Samples only while the app is running or iOS wakes it. Never claims to
/// provide permanent 1-minute background monitoring on stock iOS.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var samples: [BatterySample] = []
    @Published private(set) var liveSample: BatterySample?
    @Published private(set) var accessories: [AccessoryBattery] = []
    @Published private(set) var scanning = false
    @Published var bluetoothMessage: String?

    private let ble = BluetoothBatteryScanner()
    private var bleReadings: [AccessoryBattery] = []
    private var importedReadings: [AccessoryBattery] = []
    private var archivedAccessories: [AccessoryBattery] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var lastWidgetRefresh: Date = .distantPast
    private var lastWidgetSignature = ""

    var latest: BatterySample? { liveSample ?? samples.last }
    var hasDiagnostics: Bool { latest?.source == .diagnostic }
    var findMyBLEAccessible: Bool { FindMyBLEBridge.available }
    @Published private(set) var lastFindMySync: Date?
    var widgetShared: Bool { SharedBatteryStore.sharedContainerAvailable }

    init() {
        let archive = SharedBatteryStore.read()
        samples = archive.samples.sorted { $0.date < $1.date }
        archivedAccessories = archive.accessories
        accessories = archive.accessories

        ble.onChange = { [weak self] devices in
            self?.bleReadings = devices
            self?.mergeAccessories()
        }
        ble.onScanningChange = { [weak self] state in self?.scanning = state }
        ble.onBluetoothMessage = { [weak self] value in self?.bluetoothMessage = value }
    }

    func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        // Electrical readings change within seconds. History still writes only
        // periodic observations and widgets remain governed by WidgetKit.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification,
                     UIDevice.batteryStateDidChangeNotification,
                     UIApplication.didBecomeActiveNotification,
                     UIApplication.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    func refresh() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let value = UIDevice.current.batteryLevel
        guard value >= 0 || !samples.isEmpty else { return }
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "Charging"
        case .full: state = "Full"
        case .unplugged: state = "Unplugged"
        default: state = "Unknown"
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "High"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        let metrics = HardwareMetrics.read(chargerConnected: state == "Charging" || state == "Full")
        let percentage = value >= 0 ? Double(value * 100) : (samples.last?.percentage ?? 0)
        let sample = BatterySample(
            percentage: percentage, state: state,
            thermalState: thermal,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            voltageMV: metrics?.voltageMV,
            currentMA: metrics?.currentMA,
            temperatureC: metrics?.temperatureC,
            cycleCount: metrics?.cycleCount,
            designCapacityMAh: metrics?.designCapacityMAh,
            maximumCapacityMAh: metrics?.maximumCapacityMAh,
            remainingCapacityMAh: metrics?.remainingCapacityMAh,
            source: metrics == nil ? .ios : .diagnostic,
            usbInputWatts: metrics?.usbInputWatts,
            usbInputVoltageMV: metrics?.usbInputVoltageMV,
            usbInputCurrentMA: metrics?.usbInputCurrentMA,
            sensorCount: metrics?.sensorCount,
            sensorKeys: metrics?.sensorKeys
        )
        liveSample = sample
        // Avoid duplicate readings from a burst of device notifications.
        if let previous = samples.last, sample.date.timeIntervalSince(previous.date) < 30,
           sample.percentage == previous.percentage, sample.state == previous.state,
           sample.thermalState == previous.thermalState {
            // Keep the live UI ticking without rewriting the full 14-day
            // archive on every 3-second HID sample.
            return
        }
        samples.append(sample)
        pruneSamples()
        mergeAccessories()
    }

    func scanDevices() { ble.startScan() }
    func stopScan() { ble.stopScan() }
    func connectDevice(_ id: String) { ble.connect(to: id) }
    func disconnectDevice(_ id: String) { ble.disconnect(id) }
    func syncFindMyBLE() { mergeAccessories() }

    func importFindMyBLE(_ url: URL) {
        guard let readings = FindMyBLEBridge.importURL(url) else { return }
        importedReadings = readings
        lastFindMySync = .now
        mergeAccessories()
    }

    private func pruneSamples() {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        samples.removeAll { $0.date < cutoff }
        if samples.count > 20_000 { samples.removeFirst(samples.count - 20_000) }
    }

    private func mergeAccessories() {
        let fromFindMyBLE = FindMyBLEBridge.readAccessories()
        var byID = Dictionary(uniqueKeysWithValues: archivedAccessories.map { ($0.id, $0) })
        // Prefer readings with a percentage and never replace a newer one
        // with an old/unknown value from a different source.
        for item in fromFindMyBLE + importedReadings + bleReadings {
            if let existing = byID[item.id],
               existing.percentage != nil,
               (item.percentage == nil || existing.updated > item.updated) { continue }
            byID[item.id] = item
        }
        // Do not silently delete a disconnected accessory's last reading.
        accessories = byID.values.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        archivedAccessories = accessories
        persist()
    }

    private func persist() {
        SharedBatteryStore.write(BatteryArchive(samples: samples, accessories: accessories, lastSaved: .now))
        let levelStep = latest.map { Int($0.percentage.rounded()) / 5 } ?? -1
        let deviceSignature = accessories.map {
            "\($0.id):\($0.percentage ?? -1):\($0.connected)"
        }.joined(separator: "|")
        let signature = "\(levelStep):\(latest?.state ?? "Unknown"):\(deviceSignature)"
        if signature != lastWidgetSignature || Date().timeIntervalSince(lastWidgetRefresh) > 15 * 60 {
            lastWidgetSignature = signature
            lastWidgetRefresh = .now
            WidgetCenter.shared.reloadTimelines(ofKind: "VoltScope.phone")
            WidgetCenter.shared.reloadTimelines(ofKind: "VoltScope.devices")
            WidgetCenter.shared.reloadTimelines(ofKind: "VoltScope.lock")
        }
    }

    /// Ordinary least-squares trend over actual observations, rather than
    /// turning a one-percent battery indicator step into a false 60%/h claim.
    func trend(charging: Bool, hours: Double = 6) -> BatteryTrend? {
        // Use only the latest uninterrupted charging/discharging segment.
        // Mixing separate sessions would produce misleading slopes.
        let valid = Array(samples.reversed().prefix {
            (charging ? $0.isCharging : $0.isDischarging) &&
            $0.date >= Date().addingTimeInterval(-hours * 3600)
        }.reversed())
        guard valid.count >= 3, let first = valid.first, let last = valid.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= 12 * 60 else { return nil }
        let x = valid.map { $0.date.timeIntervalSince(first.date) / 3600 }
        let y = valid.map(\.percentage)
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)
        let denominator = x.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard denominator > 0 else { return nil }
        let numerator = zip(x, y).reduce(0.0) { sum, pair in
            sum + (pair.0 - meanX) * (pair.1 - meanY)
        }
        let slope = numerator / denominator
        guard charging ? slope > 0 : slope < 0 else { return nil }
        return BatteryTrend(percentagePerHour: slope, duration: span, points: valid.count)
    }

    var remainingHours: Double? {
        guard let latest, latest.isDischarging,
              let slope = trend(charging: false)?.percentagePerHour, slope < -0.25 else { return nil }
        return min(72, latest.percentage / -slope)
    }

    var chargeHoursToFull: Double? {
        guard let latest, latest.isCharging,
              let slope = trend(charging: true)?.percentagePerHour, slope > 0.25 else { return nil }
        // Linear approximation; real charging slows significantly near full.
        return min(24, (100 - latest.percentage) / slope)
    }

    var highDrain: Bool {
        guard let rate = trend(charging: false)?.percentagePerHour else { return false }
        return rate <= -12
    }

    func dailyDrainSummary() -> [DailyDrain] {
        guard samples.count > 1 else { return [] }
        var totals: [Date: Double] = [:]
        for index in 1..<samples.count {
            let before = samples[index - 1], after = samples[index]
            guard before.isDischarging, after.isDischarging,
                  after.date.timeIntervalSince(before.date) <= 60 * 60,
                  Calendar.current.isDate(before.date, inSameDayAs: after.date) else { continue }
            let day = Calendar.current.startOfDay(for: after.date)
            totals[day, default: 0] += max(0, before.percentage - after.percentage)
        }
        return totals.sorted { $0.key > $1.key }.map { DailyDrain(id: $0.key, percentage: $0.value) }
    }
}
