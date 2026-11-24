import SwiftUI

@main
struct PulseOSApp: App {
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var sync = WatchSyncManager.shared

    // EchoLoop audio engine lives at App root so playback continues seamlessly while checking HRV or calories
    @State private var echoSettings: AppSettings
    @State private var echoLibrary = LibraryManager()
    @State private var echoEngine: AudioPlayerEngine

    init() {
        let settings = AppSettings()
        _echoSettings = State(initialValue: settings)
        _echoEngine = State(initialValue: AudioPlayerEngine(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                echoEngine: echoEngine,
                echoLibrary: echoLibrary,
                echoSettings: echoSettings
            )
            .environmentObject(health)
            .environmentObject(sync)
            .preferredColorScheme(.dark)
            .task {
                sync.activate()
                await health.requestAuthorization()
            }
            .task {
                echoEngine.libraryManager = echoLibrary
                if echoEngine.currentTrack == nil {
                    if let demo = await echoLibrary.ensureDemoTrackExists() {
                        echoEngine.loadTrack(demo, autoPlay: false)
                    }
                }
            }
        }
    }
}
