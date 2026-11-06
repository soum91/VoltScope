import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Vision

/// User-imported figures from Settings > Battery. These are shares of the
/// selected period's battery usage, NOT measured watts or battery percentage
/// points lost. Nothing is read from another app's private container.
private struct AppBatteryUsage: Identifiable, Codable {
    var name: String
    var share: Int
    var onScreenMinutes: Int?
    var backgroundMinutes: Int?

    var id: String { name.lowercased() }

    var observation: String? {
        if let backgroundMinutes, backgroundMinutes >= 6 * 60 {
            return "Long-running background activity"
        }
        if share >= 4, let onScreenMinutes, onScreenMinutes <= 20,
           (backgroundMinutes ?? 0) <= 20 {
            return "Notable share during brief use"
        }
        return nil
    }
}

private struct BatteryOCRLine {
    let text: String
    let x: CGFloat
    let y: CGFloat
}

/// Reads only screenshots chosen by the user. Recognition is local (Vision).
private enum BatteryUsageOCR {
    static func extract(from data: Data) throws -> [AppBatteryUsage] {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw NSError(domain: "VoltScope.BatteryOCR", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a readable image."])
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        let lines: [BatteryOCRLine] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return BatteryOCRLine(text: text, x: observation.boundingBox.minX,
                                  y: observation.boundingBox.midY)
        }
        let ordered = lines.sorted { $0.y > $1.y }
        let percentages = ordered.compactMap { line -> (BatteryOCRLine, Int)? in
            guard line.x > 0.65, let share = percentage(from: line.text) else { return nil }
            return (line, share)
        }

        var found: [AppBatteryUsage] = []
        for (percentLine, share) in percentages {
            guard let title = ordered.filter({ $0.x < 0.65 && abs($0.y - percentLine.y) < 0.026
                && isPlausibleAppName($0.text) })
                .min(by: { abs($0.y - percentLine.y) < abs($1.y - percentLine.y) }) else { continue }

            let nextTitleY = percentages.compactMap { other -> CGFloat? in
                guard other.0.y < percentLine.y - 0.03 else { return nil }
                return other.0.y
            }.max() ?? -1
            let detailLines = ordered.filter { $0.x < 0.75 && $0.y < title.y - 0.006
                && $0.y > max(title.y - 0.135, nextTitleY + 0.012) }
            let onScreen = detailLines.first(where: { $0.text.lowercased().contains("on screen") })
                .flatMap { durationMinutes(from: $0.text) }
            let background = detailLines.first(where: { $0.text.lowercased().contains("background") })
                .flatMap { durationMinutes(from: $0.text) }
            found.append(AppBatteryUsage(name: title.text, share: share,
                                         onScreenMinutes: onScreen, backgroundMinutes: background))
        }
        // Repeated/overlapping screenshots are expected; never add percentages.
        var unique: [String: AppBatteryUsage] = [:]
        for item in found {
            if let previous = unique[item.id] {
                let newDetails = (item.onScreenMinutes == nil ? 0 : 1) + (item.backgroundMinutes == nil ? 0 : 1)
                let oldDetails = (previous.onScreenMinutes == nil ? 0 : 1) + (previous.backgroundMinutes == nil ? 0 : 1)
                if newDetails >= oldDetails { unique[item.id] = item }
            } else {
                unique[item.id] = item
            }
        }
        return unique.values.sorted { $0.share > $1.share }
    }

    private static func isPlausibleAppName(_ text: String) -> Bool {
        guard text.count >= 2 && text.count <= 50 else { return false }
        let lower = text.lowercased()
        return !["on screen", "background", "battery usage", "show more", "screen active",
                  "screen idle", "daily usage", "nov ", "other battery"].contains(where: lower.contains)
            && !lower.contains(":") && !lower.contains("%")
    }

    private static func percentage(from text: String) -> Int? {
        guard let range = text.range(of: #"^\s*(\d{1,3})\s*%\s*$"#, options: .regularExpression),
              let number = Int(text[range].replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)), (0...100).contains(number) else { return nil }
        return number
    }

    private static func durationMinutes(from text: String) -> Int? {
        let lower = text.lowercased()
        func number(before suffix: String) -> Int? {
            guard let match = lower.range(of: #"\d+\s*"# + suffix, options: .regularExpression) else { return nil }
            return Int(String(lower[match].filter(\.isNumber)))
        }
        let hours = number(before: "h")
        let minutes = number(before: "m")
        guard hours != nil || minutes != nil else { return nil }
        return (hours ?? 0) * 60 + (minutes ?? 0)
    }
}

@MainActor
private final class BatteryDetectiveStore: ObservableObject {
    @Published private(set) var items: [AppBatteryUsage] = []
    @Published private(set) var importedAt: Date?
    @Published private(set) var scanning = false
    @Published var message: String?

    private static let itemsKey = "VoltScope.batteryDetective.apps.v1"
    private static let dateKey = "VoltScope.batteryDetective.importedAt.v1"

    init() {
        if let saved = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([AppBatteryUsage].self, from: saved) {
            items = decoded
        }
        importedAt = UserDefaults.standard.object(forKey: Self.dateKey) as? Date
    }

    func importScreenshots(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        scanning = true
        defer { scanning = false }
        var merged = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var recognized = 0
        for data in images {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try BatteryUsageOCR.extract(from: data)
                }.value
                for item in parsed {
                    if let old = merged[item.id] {
                        // Fill missing duration details from an overlapping crop.
                        merged[item.id] = AppBatteryUsage(name: item.name, share: item.share,
                            onScreenMinutes: item.onScreenMinutes ?? old.onScreenMinutes,
                            backgroundMinutes: item.backgroundMinutes ?? old.backgroundMinutes)
                    } else {
                        merged[item.id] = item
                    }
                    recognized += 1
                }
            } catch {
                message = "Could not read screenshot: \(error.localizedDescription)"
            }
        }
        guard recognized > 0 else {
            message = "No app rows were recognized. Import a screenshot showing Settings → Battery → Battery Usage by App, including names and percentages."
            return
        }
        items = merged.values.sorted { $0.share > $1.share }
        importedAt = .now
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: Self.itemsKey)
        }
        UserDefaults.standard.set(importedAt, forKey: Self.dateKey)
        message = "Read \(recognized) app row\(recognized == 1 ? "" : "s"). Repeated rows were merged, not added together."
    }

    func clear() {
        items = []
        importedAt = nil
        message = nil
        UserDefaults.standard.removeObject(forKey: Self.itemsKey)
        UserDefaults.standard.removeObject(forKey: Self.dateKey)
    }
}

struct BatteryDetectiveView: View {
    @StateObject private var store = BatteryDetectiveStore()
    @State private var photos: [PhotosPickerItem] = []
    @State private var filesPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass.circle.fill").foregroundStyle(.cyan)
                Text("Battery Detective").font(.headline)
                Spacer()
                if !store.items.isEmpty {
                    Button("Clear", role: .destructive) { store.clear() }.font(.caption)
                }
            }
            Text("Import Apple's Battery Usage by App screenshots. Text recognition stays on your iPhone; battery percentages are Apple's usage shares, not watts measured per app.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 9) {
                PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.borderedProminent)
                Button { filesPresented = true } label: {
                    Label("Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .disabled(store.scanning)

            if store.scanning { ProgressView("Reading screenshots on device…") }
            if let message = store.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if !store.items.isEmpty {
                if let importedAt = store.importedAt {
                    Text("Last imported \(importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(item.share)%").font(.headline.monospacedDigit()).foregroundStyle(.cyan)
                        }
                        ProgressView(value: Double(item.share), total: 100)
                            .tint(item.observation == nil ? .cyan : .orange)
                        HStack(spacing: 11) {
                            if let minutes = item.onScreenMinutes {
                                Text("Screen \(duration(minutes))")
                            }
                            if let minutes = item.backgroundMinutes {
                                Text("Background \(duration(minutes))")
                            }
                        }.font(.caption2).foregroundStyle(.secondary)
                        if let observation = item.observation {
                            Label(observation, systemImage: "exclamationmark.magnifyingglass")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    if item.id != store.items.last?.id { Divider().opacity(0.3) }
                }
                Text("Flags are leads for investigation, not proof of an app's exact electrical consumption. Import screenshots from the same selected day; Clear before switching days.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("No app statistics imported yet", systemImage: "chart.bar.doc.horizontal")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .onChange(of: photos) { selected in
            Task {
                var data: [Data] = []
                for photo in selected {
                    if let bytes = try? await photo.loadTransferable(type: Data.self) {
                        data.append(bytes)
                    }
                }
                await store.importScreenshots(data)
                photos = []
            }
        }
        .fileImporter(isPresented: $filesPresented, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    var images: [Data] = []
                    for url in urls {
                        let granted = url.startAccessingSecurityScopedResource()
                        if let data = try? Data(contentsOf: url) { images.append(data) }
                        if granted { url.stopAccessingSecurityScopedResource() }
                    }
                    await store.importScreenshots(images)
                }
            case .failure(let error):
                store.message = error.localizedDescription
            }
        }
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
