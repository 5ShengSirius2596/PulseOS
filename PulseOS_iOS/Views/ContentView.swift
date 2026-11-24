import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var sync: WatchSyncManager

    @Bindable var echoEngine: AudioPlayerEngine
    @Bindable var echoLibrary: LibraryManager
    @Bindable var echoSettings: AppSettings

    @State private var showSkinSheet = false

    var body: some View {
        TabView {
            NavigationStack {
                TodayDashboardView()
                    .navigationTitle("健康总览")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSkinSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(health.snapshot.stateLevel.color)
                                        .frame(width: 8, height: 8)
                                    Text(sync.selectedSkin.displayName)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    }
            }
            .tabItem {
                Label("今日状态", systemImage: "heart.text.square.fill")
            }

            NavigationStack {
                TrendsView()
                    .navigationTitle("趋势复盘")
            }
            .tabItem {
                Label("趋势复盘", systemImage: "chart.xyaxis.line")
            }

            EchoLoopRootView(
                engine: echoEngine,
                library: echoLibrary,
                settings: echoSettings
            )
            .tabItem {
                Label("英语复读", systemImage: "waveform.circle.fill")
            }
        }
        .sheet(isPresented: $showSkinSheet) {
            SkinStudioSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
