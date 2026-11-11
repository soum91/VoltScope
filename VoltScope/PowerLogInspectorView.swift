import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct PowerLogTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct PowerLogInspectorView: View {
    @State private var data: [String: String] = [:]
    @State private var scanning = false
    @State private var lastChecked: Date?
    @State private var resultMessage: String?
    @State private var exportDoc: PowerLogTextFile?
    @State private var exporting = false

    private var status: String { data["status"] ?? "Checking access…" }
    private var isOpen: Bool { status == "PowerLog database accessible" }
    private var completeLog: String {
        let bundle = Bundle.main
        return [
            "VoltScope PowerLog access diagnostics",
            "Installed: \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))",
            "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
            "Checked: \(lastChecked.map { ISO8601DateFormatter().string(from: $0) } ?? "not yet")",
            "Status: \(status)",
            data["details"] ?? "No additional details",
            "Relevant PowerLog tables: \(data["schema"] ?? "Not checked")",
            "Background-runtime samples: \(data["runtime"] ?? "Not checked")",
            "This probe never modifies PowerLog; an App Group sandbox token is not root access."
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isOpen ? "checkmark.shield.fill" : "externaldrive.badge.magnifyingglass")
                    .foregroundStyle(isOpen ? .green : .cyan)
                Text("On-device PowerLog").font(.headline)
                Spacer()
                if scanning { ProgressView() }
            }
            Text("Attempts to read Apple's per-app energy records directly on iOS 27 using the signed App Group. No screenshots, Windows companion or background location tracking.")
                .font(.caption).foregroundStyle(.secondary)
            Text(status).font(.subheadline.weight(.semibold))
                .foregroundStyle(isOpen ? .green : .orange)
            if isOpen {
                Text("The PowerLog file opened. Table names and any identifiable app-runtime records are shown below. Raw runtime figures are not measured watts.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !scanning {
                Text("If access is denied, this screen reports the actual sandbox or file-permission error. A token does not bypass root-owned file permissions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let runtimes = data["runtime"], !runtimes.isEmpty {
                Text("Recorded background activity").font(.subheadline.bold())
                Text(runtimes).font(.caption.monospaced()).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await check() }
                } label: { Label(scanning ? "Checking" : "Refresh", systemImage: "arrow.clockwise") }
                    .disabled(scanning)
                    .buttonStyle(.borderedProminent)
                ShareLink(item: completeLog) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 10) {
                Button {
                    let report = completeLog
                    UIPasteboard.general.string = report
                    resultMessage = UIPasteboard.general.string == report ? "Complete report copied and verified" : "Clipboard verification failed. Use Share or Save."
                } label: { Label("Copy report", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered)
                Button {
                    exportDoc = PowerLogTextFile(text: completeLog)
                    exporting = true
                } label: { Label("Save .txt", systemImage: "folder") }
                    .buttonStyle(.bordered)
            }
            if let resultMessage {
                Text(resultMessage).font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("Detailed access report") {
                Text(completeLog)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }.font(.caption.weight(.medium))
        }
        .task { if lastChecked == nil { await check() } }
        .fileExporter(isPresented: $exporting, document: exportDoc,
                      contentType: .plainText, defaultFilename: "VoltScope-PowerLog-Diagnostics") { result in
            if case .failure(let error) = result { resultMessage = "Save failed: \(error.localizedDescription)" }
            else { resultMessage = "Report saved to Files" }
        }
    }

    @MainActor
    private func check() async {
        guard !scanning else { return }
        scanning = true
        resultMessage = nil
        let response = await Task.detached(priority: .utility) { VSProbePowerLog() as? [String: String] ?? [:] }.value
        data = response
        lastChecked = .now
        scanning = false
    }
}
