import SwiftUI

@main
struct VoltScopeApp: App {
    @StateObject private var service = BatteryService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service)
                .preferredColorScheme(.dark)
                .onAppear { service.start() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { service.refresh() }
                }
        }
    }
}
