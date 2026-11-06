import Foundation

struct HardwareMetrics {
    var voltageMV: Double?
    var currentMA: Double?
    var temperatureC: Double?
    var cycleCount: Int?
    var designCapacityMAh: Double?
    var maximumCapacityMAh: Double?
    var remainingCapacityMAh: Double?
    var usbInputVoltageMV: Double?
    var usbInputCurrentMA: Double?
    var usbInputWatts: Double?
    var sensorCount: Int = 0
    var sensorKeys: [String] = []

    // Exactly one HID event-system client per process. Creating more than one
    // can cause the system to respond with NaNs on subsequent reads.
    private static let hid = PrivatePowerSensors()

    static func read(chargerConnected: Bool) -> HardwareMetrics? {
        let registry = readRegistry()
        let live = hid?.read(chargerConnected: chargerConnected)
        var result = registry ?? HardwareMetrics()
        result.voltageMV = result.voltageMV ?? live?.batteryVoltageMV
        result.currentMA = result.currentMA ?? live?.chargeCurrentMA
        result.temperatureC = result.temperatureC ?? live?.batteryTemperatureC
        result.usbInputVoltageMV = live?.usbVoltageMV
        result.usbInputCurrentMA = live?.usbCurrentMA
        result.usbInputWatts = live?.usbInputWatts
        result.sensorCount = live?.serviceCount ?? 0
        result.sensorKeys = live?.measuredKeys ?? []
        guard result.voltageMV != nil || result.currentMA != nil || result.temperatureC != nil ||
              result.cycleCount != nil || result.maximumCapacityMAh != nil || result.usbInputWatts != nil else {
            return nil
        }
        return result
    }

    private static func readRegistry() -> HardwareMetrics? {
        guard let buffer = VSReadBatteryPropertiesPlist() else { return nil }
        defer { VSFreeBatteryPropertiesPlist(buffer) }
        guard let data = String(cString: buffer).data(using: .utf8) else { return nil }
        guard let dictionary = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }

        func number(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = dictionary[key] as? NSNumber { return value.doubleValue }
            }
            return nil
        }
        func capacity(_ keys: [String]) -> Double? {
            guard let n = number(keys), n > 100, n < 20_000 else { return nil }
            return n
        }

        let v = number(["Voltage", "BatteryVoltage"])
        let a = number(["InstantAmperage", "Amperage", "BatteryCurrent"])
        let t = number(["Temperature", "BatteryTemperature"])

        // AppleSmartBattery reports vary with battery controller and iOS version.
        // Do not display nonsensical units or fabricate a reading on unsupported devices.
        let voltage = v.flatMap { (2_000...6_000).contains($0) ? $0 : nil }
        let current = a.flatMap { (-30_000...30_000).contains($0) ? $0 : nil }
        let temperature: Double? = t.flatMap {
            if (-10...75).contains($0) { return $0 }
            let centiDegrees = $0 / 100
            if (-10...75).contains(centiDegrees) { return centiDegrees }
            let deciKelvin = ($0 / 10) - 273.15
            if (-10...75).contains(deciKelvin) { return deciKelvin }
            return nil
        }

        let metrics = HardwareMetrics(
            voltageMV: voltage,
            currentMA: current,
            temperatureC: temperature,
            cycleCount: number(["CycleCount", "BatteryCycleCount"]).flatMap { $0 >= 0 ? Int($0) : nil },
            designCapacityMAh: capacity(["DesignCapacity", "BatteryDesignCapacity"]),
            maximumCapacityMAh: capacity(["AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"]),
            remainingCapacityMAh: capacity(["AppleRawCurrentCapacity", "BatteryCurrentCapacity", "CurrentCapacity"])
        )
        return (metrics.voltageMV != nil || metrics.currentMA != nil || metrics.temperatureC != nil || metrics.cycleCount != nil || metrics.maximumCapacityMAh != nil)
            ? metrics : nil
    }
}
