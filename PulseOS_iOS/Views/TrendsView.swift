import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var health: HealthKitManager

    private var snap: HealthSnapshot { health.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("个人 30 天对数基线（lnSDNN）")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        statBox(label: "基线均值", value: "\(Int(snap.baselineMeanMs.rounded())) ms")
                        statBox(label: "ln(μ)", value: String(format: "%.2f", snap.baselineLnMu))
                        statBox(label: "ln(σ)", value: String(format: "%.2f", snap.baselineLnSigma))
                    }

                    Text("系统基于最近 30 天 HRV 样本的对数均值与标准差，动态划分 5 档生理压力区间，并直接驱动 Apple Watch 复杂功能自动切图。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("近期 HRV 波动曲线")
                        .font(.subheadline.weight(.semibold))
                    Chart(snap.intradayHRV) { pt in
                        AreaMark(
                            x: .value("时间", pt.date),
                            y: .value("HRV", pt.sdnnMs)
                        )
                        .foregroundStyle(snap.stateLevel.color.opacity(0.18))

                        LineMark(
                            x: .value("时间", pt.date),
                            y: .value("HRV", pt.sdnnMs)
                        )
                        .foregroundStyle(snap.stateLevel.color)
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 160)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func statBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
