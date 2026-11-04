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

    var isStale: Bool { Date().timeIntervalSince(updated) > 15 * 60 }
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

    static var sharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    private static var localURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(filename)
    }

    private static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename)
    }

    static func read() -> BatteryArchive {
        let locations = [sharedURL, localURL].compactMap { $0 }
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
        if let sharedURL {
            try? data.write(to: sharedURL, options: .atomic)
        }
    }
}
