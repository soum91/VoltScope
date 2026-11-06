import Foundation

enum ReadingSource: String, Codable {
    case ios = "iOS"
    case diagnostic = "Device diagnostics"
    case bluetooth = "Bluetooth"
    case findMyBLE = "FindMyBLE"
}

struct BatterySample: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = .now
    var percentage: Double
    var state: String
    var thermalState: String
    var lowPowerMode: Bool
    var voltageMV: Double?
    var currentMA: Double?
    var temperatureC: Double?
    var cycleCount: Int?
    var designCapacityMAh: Double?
    var maximumCapacityMAh: Double?
    var remainingCapacityMAh: Double?
    var source: ReadingSource
    /// Only the input power actually measured by USB-C sensors. Nil for
    /// wireless or partial USB-path measurements, never estimated from %.
    var usbInputWatts: Double? = nil
    var usbInputVoltageMV: Double? = nil
    var usbInputCurrentMA: Double? = nil
    var sensorCount: Int? = nil
    var sensorKeys: [String]? = nil

    var watts: Double? {
        guard let voltageMV, let currentMA else { return nil }
        return abs(voltageMV * currentMA) / 1_000_000
    }

    var healthPercentage: Double? {
        guard let designCapacityMAh, let maximumCapacityMAh, designCapacityMAh > 0 else { return nil }
        return (maximumCapacityMAh / designCapacityMAh) * 100
    }

    var isCharging: Bool { state == "Charging" }
    var isDischarging: Bool { state == "Unplugged" }
}

struct AccessoryBattery: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var percentage: Int?
    var connected: Bool
    var rssi: Int?
    var updated: Date
    var source: ReadingSource
    var note: String?
    /// Stable display hint supplied by FindMyBLE / Find My when available.
    var kind: String? = nil

    var isStale: Bool { Date().timeIntervalSince(updated) > 15 * 60 }

    var iconName: String {
        let value = "\(name) \(kind ?? "")".lowercased()
        if value.contains("airpod") && value.contains("case") { return "airpodspro.chargingcase" }
        if value.contains("airpod") { return "airpodspro" }
        if value.contains("watch") { return "applewatch" }
        if value.contains("iphone") { return "iphone" }
        if value.contains("ipad") { return "ipad" }
        if value.contains("mac") || value.contains("laptop") { return "laptopcomputer" }
        if value.contains("bottle") || value.contains("larq") { return "drop.fill" }
        if value.contains("headphone") { return "headphones" }
        if value.contains("bag") { return "bag.fill" }
        if value.contains("key") { return "key.fill" }
        if value.contains("tag") { return "tag.fill" }
        return "battery.100percent"
    }

    var displayName: String {
        let value = "\(name) \(kind ?? "")".lowercased()
        if value.contains("airpod") && value.contains("case") { return "AirPods Case" }
        if value.contains("airpod") { return "AirPods" }
        if value.contains("watch") { return "Watch" }
        if value.contains("bottle") || value.contains("larq") { return "LARQ" }
        return name
    }
}

struct BatteryArchive: Codable {
    var samples: [BatterySample] = []
    var accessories: [AccessoryBattery] = []
    var lastSaved: Date = .distantPast
}

/// A widget does not run the app's battery or Bluetooth code. It reads the last
/// observed snapshot; WidgetKit controls when it can refresh its timeline.
enum SharedBatteryStore {
    static let groupID = "group.com.soumen.voltscope"
    private static let filename = "voltscope-archive.json"

    static var sharedContainerAvailable: Bool { !sharedURLs.isEmpty }

    /// A sideloader may rewrite the App Group identifier. Read only groups
    /// present in the installed signature or AltStore metadata, plus our default.
    static let signedGroupIDs: [String] = {
        var ids = [groupID, "group.com.soumen.findmyble"]
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            ids.append(contentsOf: alt)
        }
        let sources = [Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
                       Bundle.main.executableURL].compactMap { $0 }
        for file in sources {
            guard let stream = InputStream(url: file) else { continue }
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            var overlap = Data()
            while stream.hasBytesAvailable {
                let n = stream.read(&bytes, maxLength: bytes.count)
                if n <= 0 { break }
                var data = overlap
                data.append(contentsOf: bytes[..<n])
                let text = String(decoding: data, as: UTF8.self)
                    let pattern = #"group\.[A-Za-z0-9_.-]+"#
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(text.startIndex..<text.endIndex, in: text)
                        for match in regex.matches(in: text, range: range) {
                            if let r = Range(match.range, in: text) { ids.append(String(text[r])) }
                        }
                    }
                overlap = Data(data.suffix(2048))
            }
        }
        return Array(Set(ids)).sorted()
    }()

    static let sharedURLs: [URL] = {
        signedGroupIDs.filter { $0.contains("voltscope") }
            .compactMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }()

    private static var localURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(filename)
    }

    private static var sharedURL: URL? { sharedURLs.first?.appendingPathComponent(filename) }

    static func read() -> BatteryArchive {
        let locations = sharedURLs.map { $0.appendingPathComponent(filename) } + [localURL]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        for url in locations {
            if let data = try? Data(contentsOf: url),
               let archive = try? decoder.decode(BatteryArchive.self, from: data) {
                return archive
            }
        }
        return BatteryArchive()
    }

    static func write(_ archive: BatteryArchive) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(archive) else { return }
        // Keep the main app functional even if a sideloader strips App Groups.
        try? data.write(to: localURL, options: .atomic)
        for sharedURL in sharedURLs.map({ $0.appendingPathComponent(filename) }) {
            try? data.write(to: sharedURL, options: .atomic)
        }
    }
}
