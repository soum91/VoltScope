import Foundation

/// Read-only bridge to the existing FindMyBLE widget cache. This does not ask
/// the LARQ cap to connect twice and does not need FindMyBLE credentials.
/// It works only when both apps are signed with access to the SAME App Group.
enum FindMyBLEBridge {
    static let groupID = "group.com.soumen.findmyble"

    static var available: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static func readAccessories() -> [AccessoryBattery] {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("snapshot.json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let name = item["title"] as? String else { return nil }
            let level = item["battery"] as? Int
            let timestamp = item["batteryAt"] as? Double
            return AccessoryBattery(
                id: "findmyble:\(id)", name: name,
                percentage: level.flatMap { (0...100).contains($0) ? $0 : nil },
                connected: item["isConnected"] as? Bool ?? false,
                rssi: nil,
                updated: timestamp.map { Date(timeIntervalSince1970: $0) } ?? .distantPast,
                source: .findMyBLE,
                note: "Cached by FindMyBLE • LARQ and tracked items"
            )
        }
    }
}
