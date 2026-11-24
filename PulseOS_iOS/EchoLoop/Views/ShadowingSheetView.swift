import SwiftUI

/// 录音跟读与原声波形对比面板
struct ShadowingSheetView: View {
    @Bindable var engine: AudioPlayerEngine
    @State private var recorder = ShadowingRecorder()
    @Environment(\.dismiss) private var dismiss

    private var originalSliceSamples: [Float] {
        guard !engine.waveformSamples.isEmpty, engine.waveformRateHz > 0 else { return [] }
        let startIdx = max(0, Int(engine.activeRange.start * engine.waveformRateHz))
        let endIdx = min(engine.waveformSamples.count - 1, Int(engine.activeRange.end * engine.waveformRateHz))
        guard startIdx <= endIdx else { return [] }
        return Array(engine.waveformSamples[startIdx...endIdx])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 当前跟读句子文本
                if let seg = engine.currentSegment, !seg.text.isEmpty {
                    VStack(spacing: 6) {
                        Text(seg.text)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        if !seg.translation.isEmpty {
                            Text(seg.translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)
                }

                // 原声波形 vs 跟读波形对比卡片
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("原声波形", systemImage: "waveform")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("\(TimeFormatters.mmssTenth(engine.activeRange.start)) - \(TimeFormatters.mmssTenth(engine.activeRange.end))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        MiniWaveformBarView(samples: originalSliceSamples, color: .blue)
                            .frame(height: 58)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("我的跟读波形", systemImage: "mic.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                            Text(TimeFormatters.mmssTenth(recorder.recordingDuration))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if recorder.recordedWaveform.isEmpty {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.08))
                                .frame(height: 58)
                                .overlay {
                                    Text("点击下方红色按钮开始跟读录音")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                        } else {
                            MiniWaveformBarView(samples: recorder.recordedWaveform, color: .orange)
                                .frame(height: 58)
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                if let err = recorder.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // 操作按钮组：听原声 / 录音 / 听自己
                HStack(spacing: 28) {
                    Button {
                        recorder.stopPlayback()
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.seek(to: engine.activeRange.start)
                            engine.play()
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: engine.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.blue)
                            Text(engine.isPlaying ? "停止原声" : "播放原声")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.pause()
                        recorder.toggleRecording()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(recorder.isRecording ? Color.red.opacity(0.2) : Color.red.opacity(0.12))
                                    .frame(width: 74, height: 74)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: recorder.isRecording ? 32 : 56, height: recorder.isRecording ? 32 : 56)
                                    .clipShape(RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 28))
                            }
                            Text(recorder.isRecording ? "停止录音" : "开始跟读")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.pause()
                        recorder.togglePlayRecording()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: recorder.isPlayingRecording ? "stop.circle.fill" : "waveform.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(recorder.hasRecording ? .orange : .gray.opacity(0.4))
                            Text(recorder.isPlayingRecording ? "停止回放" : "听我的")
                                .font(.caption)
                                .foregroundStyle(recorder.hasRecording ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!recorder.hasRecording)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
            .navigationTitle("录音跟读对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        recorder.stopRecording()
                        recorder.stopPlayback()
                        engine.configureAudioSessionForPlayback()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                recorder.stopRecording()
                recorder.stopPlayback()
                engine.configureAudioSessionForPlayback()
            }
        }
    }
}

struct MiniWaveformBarView: View {
    let samples: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let count = min(samples.count, 100)
            let strideStep = max(1, samples.count / count)
            let barWidth = size.width / CGFloat(count)
            let midY = size.height / 2.0

            for i in 0..<count {
                let sampleIdx = min(samples.count - 1, i * strideStep)
                let amp = CGFloat(max(0.06, samples[sampleIdx]))
                let halfH = amp * (size.height * 0.45)
                let x = CGFloat(i) * barWidth + barWidth / 2.0
                var path = Path()
                path.move(to: CGPoint(x: x, y: midY - halfH))
                path.addLine(to: CGPoint(x: x, y: midY + halfH))
                context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: max(1.5, barWidth * 0.55))
            }
        }
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
