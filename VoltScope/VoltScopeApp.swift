import SwiftUI

@main
struct VoltScopeApp: App {
    @StateObject private var service = BatteryService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The PowerLog probe briefly swaps only our App Group Caches entry.
        // Restore it after an interrupted launch before using shared data.
        _ = VSRecoverPowerLogCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service)
                .preferredColorScheme(.dark)
                .onAppear { service.start() }
                .onOpenURL { url in service.importFindMyBLE(url) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { service.refresh() }
                }
        }
    }
}
