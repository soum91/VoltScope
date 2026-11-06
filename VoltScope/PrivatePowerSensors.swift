import Foundation
import Darwin

/// Read-only, best-effort Apple vendor HID telemetry. This does not escape the
/// sandbox or request elevated entitlements. Some iOS versions and devices will
/// not publish these services, in which case every measurement remains absent.
///
/// Technique adapted from Greg Wilson's ios-charging-monitor (MIT), with sensor
/// identity/validation informed by ZhaoHe Studio's MiniWatts (Apache-2.0).
/// See THIRD_PARTY_NOTICES.md before redistributing.
final class PrivatePowerSensors {
    struct Snapshot {
        var batteryVoltageMV: Double?
        var chargeCurrentMA: Double?
        var batteryTemperatureC: Double?
        var usbVoltageMV: Double?
        var usbCurrentMA: Double?
        var usbInputWatts: Double?
        var serviceCount: Int
        var measuredKeys: [String]
    }

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatFn = @convention(c) (CFTypeRef, Int32) -> Double

    private struct Service {
        let ref: CFTypeRef
        let name: String
        let key: String
        let usage: Int
        let eventType: Int64
    }

    private let handle: UnsafeMutableRawPointer
    private let client: CFTypeRef
    private let setMatching: SetMatchingFn
    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private var services: [Service] = []
    private var lastRescan: Date = .distantPast
    private var lastChargerState: Bool?

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL) else { return nil }
        func resolve<T>(_ name: String, as _: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        guard let create = resolve("IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = resolve("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = resolve("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = resolve("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = resolve("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let getFloat = resolve("IOHIDEventGetFloatValue", as: GetFloatFn.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.client = client
        self.setMatching = setMatching
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat
        rescan()
    }

    deinit { dlclose(handle) }

    private func rescan() {
        let power = discover(["PrimaryUsagePage": 0xff08], type: 25)
        let temperature = discover(["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5], type: 15)
        services = power + temperature
        lastRescan = .now
    }

    private func discover(_ matching: [String: Any], type: Int64) -> [Service] {
        setMatching(client, matching as CFDictionary)
        let refs = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
        return refs.map { ref in
            let name = copyProperty(ref, "Product" as CFString)?.takeRetainedValue() as? String ?? "Unknown"
            let usage = (copyProperty(ref, "PrimaryUsage" as CFString)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            let location = (copyProperty(ref, "LocationID" as CFString)?.takeRetainedValue() as? NSNumber)?.uint32Value ?? 0
            let bytes = withUnsafeBytes(of: location.bigEndian) { Array($0) }
            let key = location != 0 && bytes.allSatisfy({ (32...126).contains($0) })
                ? String(decoding: bytes, as: UTF8.self) : ""
            return Service(ref: ref, name: name, key: key, usage: usage, eventType: type)
        }
    }

    private func value(of service: Service) -> Double? {
        let count = ["IQ0B", "IQ0u"].contains(service.key) ? 4 : 1
        let readings: [Double] = (0..<count).compactMap { _ in
            guard let event = copyEvent(service.ref, service.eventType, 0, 0)?.takeRetainedValue() else { return nil }
            let value = getFloat(event, Int32(service.eventType << 16))
            return value.isFinite && abs(value) < 1000 ? value : nil
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    func read(chargerConnected: Bool) -> Snapshot {
        // Charger endpoints may only appear once USB-C or MagSafe is connected.
        if lastChargerState != chargerConnected || Date().timeIntervalSince(lastRescan) > 15 {
            rescan()
            lastChargerState = chargerConnected
        }

        var byKey: [String: Double] = [:]
        var batteryTemperatures: [Double] = []
        for service in services {
            guard let reading = value(of: service) else { continue }
            if !service.key.isEmpty, byKey[service.key] == nil { byKey[service.key] = reading }
            if service.usage == 5,
               (service.key.hasPrefix("TG0") || service.name.lowercased().contains("gas gauge battery")),
               (-10...75).contains(reading) {
                batteryTemperatures.append(reading)
            }
        }

        func valid(_ key: String, range: ClosedRange<Double>) -> Double? {
            guard let value = byKey[key], range.contains(value) else { return nil }
            return value
        }
        let batteryVoltage = valid("VQ0l", range: 2.5...5.5) ?? valid("VP0u", range: 2.5...5.5)
        let usbVoltage = valid("VQ0u", range: 2...25)
        let usbCurrent = valid("IQ0u", range: 0...10)
        // IQ0B is a charge-to-cell sensor; it returns 0 on battery power.
        // Suppress it when unplugged so it is never mistaken for discharge current.
        let chargeCurrent = chargerConnected ? valid("IQ0B", range: 0...10) : nil
        let rawInput: Double?
        if let usbVoltage, let usbCurrent {
            rawInput = usbVoltage * usbCurrent
        } else {
            rawInput = nil
        }
        let batteryWatts = batteryVoltage.flatMap { voltage in chargeCurrent.map { voltage * $0 } }
        // Some models report only one of several USB input paths (e.g. half of
        // total input). Suppress the total instead of presenting it as measured.
        let inputWatts = rawInput.flatMap { input in
            if let batteryWatts, batteryWatts > input * 1.10 + 0.3 { return nil }
            return input
        }
        let temperatures = batteryTemperatures.sorted()
        let batteryTemperature = temperatures.isEmpty ? nil : temperatures[temperatures.count / 2]
        return Snapshot(
            batteryVoltageMV: batteryVoltage.map { $0 * 1000 },
            chargeCurrentMA: chargeCurrent.map { $0 * 1000 },
            batteryTemperatureC: batteryTemperature,
            usbVoltageMV: inputWatts == nil ? nil : usbVoltage.map { $0 * 1000 },
            usbCurrentMA: inputWatts == nil ? nil : usbCurrent.map { $0 * 1000 },
            usbInputWatts: inputWatts,
            serviceCount: services.count,
            measuredKeys: byKey.keys.sorted()
        )
    }
}
