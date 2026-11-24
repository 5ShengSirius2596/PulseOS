import WidgetKit
import SwiftUI

struct PulseTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthSnapshot
    let skin: WatchSkinStyle
}

struct PulseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseTimelineEntry {
        PulseTimelineEntry(date: Date(), snapshot: .sample, skin: .mascot)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseTimelineEntry) -> Void) {
        let entry = PulseTimelineEntry(
            date: Date(),
            snapshot: SharedStore.shared.loadSnapshot(),
            skin: SharedStore.shared.loadSkinStyle()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseTimelineEntry>) -> Void) {
        let now = Date()
        let entry = PulseTimelineEntry(
            date: now,
            snapshot: SharedStore.shared.loadSnapshot(),
            skin: SharedStore.shared.loadSkinStyle()
        )
        // 45-minute fallback refresh guards against watchOS HKObserverQuery stalls
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 45, to: now) ?? now.addingTimeInterval(2700)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - 1. HRV Stress & Body State Complication (All 4 Watch Face Families)

struct HRVStateComplication: Widget {
    let kind = "PulseOS.HRVStateComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTimelineProvider()) { entry in
            HRVComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HRV 当前状态")
        .description("实时展示基于个人 30 日基线的 HRV 压力与恢复状态，随状态自动切换表盘皮肤。")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

struct HRVComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: PulseTimelineEntry

    private var snap: HealthSnapshot { entry.snapshot }
    private var isAccented: Bool { renderingMode != .fullColor }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            SkinGraphicView(skin: entry.skin, level: snap.stateLevel, size: 42, isAccented: isAccented)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(snap.stateLevel.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(snap.stateLevel.color)
                        .widgetAccentable()
                    Spacer(minLength: 2)
                    Text("\(Int(snap.latestHRVMs.rounded()))ms")
                        .font(.caption2.monospaced().weight(.semibold))
                }

                MiniSparklineView(points: snap.intradayHRV.map(\.sdnnMs), color: snap.stateLevel.color)
                    .frame(height: 16)
                    .widgetAccentable()

                Text("准备度 \(snap.readinessScore) · 消耗 \(Int(snap.totalKcal.rounded()))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var circularView: some View {
        ZStack {
            Gauge(value: Double(snap.stateScore), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(snap.stateLevel.color)
            .widgetAccentable()

            SkinGraphicView(skin: entry.skin, level: snap.stateLevel, size: 28, isAccented: isAccented)
        }
    }

    private var cornerView: some View {
        SkinGraphicView(skin: entry.skin, level: snap.stateLevel, size: 22, isAccented: isAccented)
            .widgetAccentable()
            .widgetLabel {
                Text("\(snap.stateLevel.shortTitle) \(Int(snap.latestHRVMs.rounded()))")
            }
    }

    private var inlineView: some View {
        Label("\(snap.stateLevel.shortTitle) · HRV \(Int(snap.latestHRVMs.rounded()))ms", systemImage: snap.stateLevel.sfSymbol)
    }
}

// MARK: - 2. Overnight Vitals Summary Complication

struct OvernightVitalsComplication: Widget {
    let kind = "PulseOS.OvernightVitalsComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTimelineProvider()) { entry in
            OvernightComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("昨晚生命体征")
        .description("汇总睡眠时长、手腕温度、呼吸频率与血氧状态。")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct OvernightComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseTimelineEntry

    private var ov: OvernightVitals { entry.snapshot.overnight }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: "bed.double.fill").foregroundStyle(.purple)
                    Text("昨晚生命体征")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Text("\(ov.normalCount)/4 正常")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .widgetAccentable()
                }
                Text(String(format: "睡眠 %.1fh · 效率 %d%%", ov.sleepHours, ov.sleepEfficiencyPct))
                    .font(.caption2.monospaced())
                if let temp = ov.wristTempCelsius, let hr = ov.sleepingHeartRate {
                    Text(String(format: "体温 %.1f°C · 心率 %.0fbpm", temp, hr))
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Label("昨晚体征 \(ov.normalCount)/4 正常", systemImage: "moon.stars.fill")
        default:
            VStack(spacing: 1) {
                Text("\(ov.normalCount)/4")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
                    .widgetAccentable()
                Text("体征")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniSparklineView: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let vals = points.count >= 2 ? Array(points.suffix(8)) : [38, 42, 40, 44]
            let minV = (vals.min() ?? 20) - 4
            let maxV = max(minV + 10, (vals.max() ?? 60) + 4)

            Path { path in
                for (i, v) in vals.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(1, vals.count - 1))
                    let y = geo.size.height * (1 - CGFloat((v - minV) / (maxV - minV)))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
