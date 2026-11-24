import SwiftUI

@main
struct PulseOSWatchApp: App {
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var sync = WatchSyncManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(health)
                .environmentObject(sync)
                .task {
                    sync.activate()
                    await health.requestAuthorization()
                }
        }
    }
}
