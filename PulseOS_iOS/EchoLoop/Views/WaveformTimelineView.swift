import SwiftUI

/// 高精度交互式波形时间轴：自适应深浅色模式，支持缩放、拖拽定位、品牌蓝紫渐变激活波形与实时播放指针
struct WaveformTimelineView: View {
    let samples: [Float]
    let sampleRateHz: Double
    let duration: TimeInterval
    let currentTime: TimeInterval
    let activeStart: TimeInterval
    let activeEnd: TimeInterval
    let segments: [AudioSegment]
    let onSeek: (TimeInterval) -> Void

    @State private var windowSeconds: Double = 6.0
    @GestureState private var zoomScale: CGFloat = 1.0

    private var effectiveWindow: Double {
        max(2.5, min(16.0, windowSeconds / Double(zoomScale)))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = max(1, geo.size.height)
            let visibleDuration = min(max(effectiveWindow, 2.0), max(duration, 2.0))

            let halfWin = visibleDuration / 2.0
            let maxStart = max(0, duration - visibleDuration)
            let windowStart = max(0, min(currentTime - halfWin, maxStart))
            let windowEnd = windowStart + visibleDuration

            ZStack(alignment: .topLeading) {
                Color(.tertiarySystemGroupedBackground).opacity(0.65)

                Canvas { context, size in
                    let rulerHeight: CGFloat = 20
                    let waveTop = rulerHeight + 6
                    let waveHeight = size.height - waveTop - 8
                    let midY = waveTop + waveHeight / 2.0

                    func xForTime(_ t: TimeInterval) -> CGFloat {
                        CGFloat((t - windowStart) / visibleDuration) * size.width
                    }

                    // 1. 当前 AB/段落柔和渐变高亮区
                    let hlLeft = max(0, xForTime(activeStart))
                    let hlRight = min(size.width, xForTime(activeEnd))
                    if hlRight > hlLeft {
                        let highlightRect = CGRect(x: hlLeft, y: rulerHeight, width: hlRight - hlLeft, height: size.height - rulerHeight)
                        context.fill(
                            Path(highlightRect),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 0.13, green: 0.57, blue: 0.96).opacity(0.18),
                                    Color(red: 0.44, green: 0.38, blue: 0.92).opacity(0.16)
                                ]),
                                startPoint: CGPoint(x: hlLeft, y: rulerHeight),
                                endPoint: CGPoint(x: hlRight, y: size.height)
                            )
                        )

                        // A/B 边界细线
                        for edgeX in [hlLeft, hlRight] {
                            var edge = Path()
                            edge.move(to: CGPoint(x: edgeX, y: rulerHeight))
                            edge.addLine(to: CGPoint(x: edgeX, y: size.height))
                            context.stroke(edge, with: .color(Color(red: 0.14, green: 0.56, blue: 0.96).opacity(0.45)), lineWidth: 1)
                        }
                    }

                    // 2. 顶部时间标尺与网格线
                    let firstSec = Int(floor(windowStart))
                    let lastSec = Int(ceil(windowEnd))
                    let stepSec = visibleDuration > 10 ? 2 : 1

                    for sec in stride(from: firstSec, through: lastSec, by: stepSec) where sec >= 0 {
                        let x = xForTime(Double(sec))
                        guard x >= -20 && x <= size.width + 20 else { continue }

                        var gridLine = Path()
                        gridLine.move(to: CGPoint(x: x, y: rulerHeight))
                        gridLine.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(gridLine, with: .color(.secondary.opacity(0.14)), lineWidth: 0.6)

                        let label = Text(TimeFormatters.mmss(Double(sec)))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        context.draw(label, at: CGPoint(x: x + 20, y: 10), anchor: .center)
                    }

                    // 3. 中轴线
                    var centerLine = Path()
                    centerLine.move(to: CGPoint(x: 0, y: midY))
                    centerLine.addLine(to: CGPoint(x: size.width, y: midY))
                    context.stroke(centerLine, with: .color(.secondary.opacity(0.18)), lineWidth: 0.7)

                    // 4. 波形柱
                    if !samples.isEmpty && sampleRateHz > 0 {
                        let startIdx = max(0, Int(floor(windowStart * sampleRateHz)))
                        let endIdx = min(samples.count - 1, Int(ceil(windowEnd * sampleRateHz)))

                        if startIdx <= endIdx {
                            let playedColor = Color(red: 0.13, green: 0.57, blue: 0.96)
                            let activeColor = Color(red: 0.42, green: 0.39, blue: 0.91)
                            let inactiveColor = Color.secondary.opacity(0.35)

                            for idx in startIdx...endIdx {
                                let t = Double(idx) / sampleRateHz
                                let x = xForTime(t)
                                let amp = CGFloat(max(0.04, samples[idx]))
                                let halfBar = amp * (waveHeight * 0.46)
                                var bar = Path()
                                bar.move(to: CGPoint(x: x, y: midY - halfBar))
                                bar.addLine(to: CGPoint(x: x, y: midY + halfBar))

                                let inActive = (t >= activeStart && t <= activeEnd)
                                let barColor: Color
                                if inActive {
                                    barColor = t <= currentTime ? playedColor : activeColor.opacity(0.85)
                                } else {
                                    barColor = inactiveColor
                                }
                                context.stroke(
                                    bar,
                                    with: .color(barColor),
                                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                                )
                            }
                        }
                    }

                    // 5. 段落分割节点
                    for seg in segments {
                        for boundary in [seg.startTime, seg.endTime] {
                            guard boundary >= windowStart && boundary <= windowEnd else { continue }
                            let bx = xForTime(boundary)
                            let dotRect = CGRect(x: bx - 3, y: midY - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: dotRect), with: .color(.secondary.opacity(0.55)))
                        }
                    }

                    // 6. 播放指针与顶部圆点
                    let playX = xForTime(currentTime)
                    if playX >= 0 && playX <= size.width {
                        var cursor = Path()
                        cursor.move(to: CGPoint(x: playX, y: rulerHeight))
                        cursor.addLine(to: CGPoint(x: playX, y: size.height))
                        context.stroke(cursor, with: .color(Color(red: 0.13, green: 0.57, blue: 0.96)), lineWidth: 2)

                        let headRect = CGRect(x: playX - 4, y: rulerHeight - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: headRect), with: .color(Color(red: 0.13, green: 0.57, blue: 0.96)))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = max(0, min(1, value.location.x / width))
                        let targetTime = windowStart + Double(ratio) * visibleDuration
                        onSeek(targetTime)
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($zoomScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        windowSeconds = max(2.5, min(16.0, windowSeconds / Double(value)))
                    }
            )
            .frame(height: height)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
