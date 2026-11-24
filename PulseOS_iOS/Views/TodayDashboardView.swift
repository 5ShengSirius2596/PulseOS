import SwiftUI
import Charts

struct TodayDashboardView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var sync: WatchSyncManager

    private var snap: HealthSnapshot { health.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hrvHeroCard
                calorieCard
                overnightVitalsCard
                cardioMetabolicCard
                daytimeActivityCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .refreshable {
            await health.refreshAll()
        }
    }

    // MARK: - 1. HRV Stress & Recovery Hero

    private var hrvHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("实时压力与恢复中枢")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "z = %+.1fσ", snap.zScore))
                    .font(.caption2.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(snap.stateLevel.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(snap.stateLevel.color)
                Spacer()
                Text(snap.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(snap.stateScore) / 100.0)
                        .stroke(snap.stateLevel.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    SkinGraphicView(skin: sync.selectedSkin, level: snap.stateLevel, size: 52)
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(snap.stateLevel.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(snap.stateLevel.color)
                        Text("\(Int(snap.latestHRVMs.rounded())) ms")
                            .font(.subheadline.monospaced().weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(snap.stateLevel.advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text("准备指数 \(snap.readinessScore)")
                            .font(.caption2.monospaced().weight(.semibold))
                        Text("30日基线 \(Int(snap.baselineMeanMs.rounded())) ms")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !snap.intradayHRV.isEmpty {
                Divider().overlay(.white.opacity(0.08))
                Chart(snap.intradayHRV) { pt in
                    LineMark(
                        x: .value("时间", pt.date),
                        y: .value("HRV", pt.sdnnMs)
                    )
                    .foregroundStyle(.white.opacity(0.45))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("时间", pt.date),
                        y: .value("HRV", pt.sdnnMs)
                    )
                    .foregroundStyle(snap.stateLevel.color)
                    .symbolSize(26)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
                }
                .frame(height: 76)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - 2. Prominent Calorie Statistics (Resting + Active)

    private var calorieCard: some View {
        let goalPct = snap.activeGoalKcal > 0 ? Int((snap.activeKcal / snap.activeGoalKcal * 100).rounded()) : 0
        let remain = max(0, Int((snap.activeGoalKcal - snap.activeKcal).rounded()))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("今日热量统计")
                    .font(.subheadline.weight(.semibold))
                Text("活动 \(goalPct)%")
                    .font(.caption2.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                Spacer()
                Text("静息 \(snap.restingRatioPct)% / 活动 \(snap.activeRatioPct)%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(snap.totalKcal.rounded()))")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("千卡 · 总消耗")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * CGFloat(snap.restingRatioPct) / 100.0))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                }
            }
            .frame(height: 11)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("静息热量").font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                        Spacer()
                        Text("基础代谢").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(Int(snap.restingKcal.rounded())) 千卡")
                        .font(.headline.monospacedDigit())
                    Text("自动由 Apple Health 估算")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("活动热量").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        Spacer()
                        Text("目标 \(Int(snap.activeGoalKcal))").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Text("\(Int(snap.activeKcal.rounded())) 千卡")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.orange)
                    Text(remain > 0 ? "距目标还差 \(remain) 千卡" : "今日活动已达标")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Chart(snap.hourlyCalories) { item in
                BarMark(
                    x: .value("小时", item.id),
                    y: .value("静息", item.restingKcal)
                )
                .foregroundStyle(.cyan.opacity(0.45))

                BarMark(
                    x: .value("小时", item.id),
                    y: .value("活动", item.activeKcal)
                )
                .foregroundStyle(.orange)
            }
            .chartXAxis {
                AxisMarks(values: [0, 12, 23]) { val in
                    AxisValueLabel {
                        if let h = val.as(Int.self) {
                            Text("\(h):00").font(.caption2.monospaced())
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 54)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - 3. Overnight Sleep & 4 Vitals Grouped

    private var overnightVitalsCard: some View {
        let ov = snap.overnight
        let hrs = Int(ov.sleepHours)
        let mins = Int(((ov.sleepHours - Double(hrs)) * 60).rounded())

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("昨晚睡眠与夜间体征")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(ov.normalCount) / 4 项正常")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(hrs)h \(mins)m")
                    .font(.title2.bold().monospacedDigit())
                Text("效率 \(ov.sleepEfficiencyPct)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text("深睡 \(ov.deepMinutes)m · REM \(ov.remMinutes)m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                vitalTile(title: "睡眠心率", value: ov.sleepingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--", tint: .red)
                vitalTile(title: "手腕温度", value: ov.wristTempCelsius.map { String(format: "%.1f °C", $0) } ?? "--", tint: .blue)
                vitalTile(title: "呼吸频率", value: ov.respiratoryRate.map { String(format: "%.1f 次/分", $0) } ?? "--", tint: .cyan)
                vitalTile(title: "夜间血氧", value: ov.bloodOxygenPct.map { "\(Int($0.rounded()))%" } ?? "--", tint: .purple)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - 4. Cardio & Metabolic Grouped

    private var cardioMetabolicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("心肺与身体代谢")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                compactMetric(title: "静息心率", value: snap.restingHeartRate.map { "\(Int($0.rounded()))" } ?? "--", unit: "bpm")
                compactMetric(title: "最大摄氧", value: snap.vo2Max.map { String(format: "%.1f", $0) } ?? "--", unit: "VO2")
                compactMetric(title: "体重", value: snap.bodyMassKg.map { String(format: "%.1f", $0) } ?? "--", unit: "kg")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - 5. Daytime Activity, Daylight & Water

    private var daytimeActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日间活动与节律")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                compactMetric(title: "今日步数", value: "\(snap.stepCount)", unit: "步")
                compactMetric(title: "锻炼时长", value: "\(snap.exerciseMinutes)", unit: "分钟")
                compactMetric(title: "晒太阳", value: "\(snap.daylightMinutes)", unit: "分钟")
            }

            Divider().overlay(.white.opacity(0.08))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("饮水记录")
                        .font(.caption.weight(.semibold))
                    Text("\(Int(snap.waterMl.rounded())) / \(Int(snap.waterGoalMl)) ml")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Button("+250 ml") {
                    Task { await health.logWater(milliliters: 250) }
                }
                .font(.caption.monospaced().weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func vitalTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactMetric(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
