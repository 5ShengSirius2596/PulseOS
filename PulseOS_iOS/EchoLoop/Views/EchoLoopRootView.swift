import SwiftUI

/// Wraps EchoLoop's Player, Files, and Profile views inside a single tab of PulseOS (avoiding nested TabViews).
struct EchoLoopRootView: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var library: LibraryManager
    @Bindable var settings: AppSettings

    @State private var selectedSubTab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("复读功能", selection: $selectedSubTab) {
                Text("播放").tag(0)
                Text("文件").tag(1)
                Text("学习统计").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Group {
                switch selectedSubTab {
                case 0:
                    PlayerView(engine: engine, library: library, settings: settings)
                case 1:
                    FilesView(engine: engine, library: library, selectedTab: $selectedSubTab)
                default:
                    ProfileView(engine: engine, library: library, settings: settings, selectedTab: $selectedSubTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Color(red: 0.14, green: 0.56, blue: 0.96))
    }
}
