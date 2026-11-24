import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var sync: WatchSyncManager

    private var snap: HealthSnapshot { health.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SkinGraphicView(skin: sync.selectedSkin, level: snap.stateLevel, size: 54)
                    .padding(.top, 4)

                Text(snap.stateLevel.title)
                    .font(.headline.bold())
                    .foregroundStyle(snap.stateLevel.color)

                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("HRV").font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int(snap.latestHRVMs.rounded()))ms").font(.caption.monospaced().bold())
                    }
                    VStack(spacing: 2) {
                        Text("准备度").font(.caption2).foregroundStyle(.secondary)
                        Text("\(snap.readinessScore)").font(.caption.monospaced().bold())
                    }
                    VStack(spacing: 2) {
                        Text("总消耗").font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int(snap.totalKcal.rounded()))").font(.caption.monospaced().bold())
                    }
                }

                Text("昨晚体征：\(snap.overnight.normalCount)/4 项正常")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await health.refreshAll() }
                } label: {
                    Label(health.isLoading ? "刷新中..." : "立即刷新表盘", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(snap.stateLevel.color)
            }
            .padding(.horizontal, 8)
        }
    }
}
