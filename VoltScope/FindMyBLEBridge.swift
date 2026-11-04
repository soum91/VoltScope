import Foundation

/// A read-only App Group bridge, plus a battery-only deep-link fallback for
/// apps signed by different teams or sideloaders that strip App Groups.
enum FindMyBLEBridge {
    static let groupID = "group.com.soumen.findmyble"

    private static var containers: [URL] {
        let candidates = SharedBatteryStore.signedGroupIDs.filter { $0.contains("findmyble") }
        return candidates.compactMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    }

    static var available: Bool { !containers.isEmpty }

    private struct Transfer: Decodable {
        let version: Int
        let updated: Double
        let items: [TransferItem]
    }

    private struct TransferItem: Decodable {
        let id: String
        let name: String
        let percentage: Int?
        let connected: Bool
        let updated: Double
        let kind: String
    }

    static func importURL(_ url: URL) -> [AccessoryBattery]? {
        guard url.scheme == "voltscope", url.host == "import-batteries",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "payload" })?.value,
              token.count <= 100_000 else { return nil }
        let base = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base + String(repeating: "=", count: (4 - base.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded) else { return nil }
        return decodeTransfer(bytes)
    }

    private static func decodeTransfer(_ data: Data) -> [AccessoryBattery]? {
        guard let decoded = try? JSONDecoder().decode(Transfer.self, from: data),
              decoded.version == 1, decoded.items.count <= 40,
              decoded.updated.isFinite else { return nil }
        return decoded.items.compactMap { item in
            guard (item.id.hasPrefix("findmyble:") || item.id.hasPrefix("findmy:")),
                  item.id.count <= 120, !item.name.isEmpty, item.name.count <= 80,
                  item.updated.isFinite,
                  item.percentage.map({ (0...100).contains($0) }) ?? true else { return nil }
            let date = Date(timeIntervalSince1970: item.updated)
            return AccessoryBattery(id: item.id, name: item.name,
                percentage: item.percentage, connected: item.connected,
                rssi: nil, updated: date, source: .findMyBLE,
                note: item.id.hasPrefix("findmy:") ? "Find My • last reported" : "FindMyBLE • last reported",
                kind: item.kind)
        }
    }

    static func readAccessories() -> [AccessoryBattery] {
        for container in containers {
            let file = container.appendingPathComponent("voltscope-batteries.json")
            if let data = try? Data(contentsOf: file),
               let readings = decodeTransfer(data) { return readings }
        }
        // Compatibility with previous FindMyBLE builds that only publish
        // their own widget snapshot. The new bridge adds Find My devices too.
        for container in containers {
            let file = container.appendingPathComponent("snapshot.json")
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["items"] as? [[String: Any]] else { continue }
            return items.compactMap { item in
                guard let id = item["id"] as? String,
                      let name = item["title"] as? String else { return nil }
                let level = item["battery"] as? Int
                let at = item["batteryAt"] as? Double
                return AccessoryBattery(
                    id: "findmyble:\(id)", name: name,
                    percentage: level.flatMap { (0...100).contains($0) ? $0 : nil },
                    connected: item["isConnected"] as? Bool ?? false,
                    rssi: nil, updated: at.map(Date.init(timeIntervalSince1970:)) ?? .distantPast,
                    source: .findMyBLE, note: "FindMyBLE • LARQ / tracked item",
                    kind: item["icon"] as? String)
            }
        }
        return []
    }
}
