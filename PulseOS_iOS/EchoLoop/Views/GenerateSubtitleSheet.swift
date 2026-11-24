import SwiftUI

/// 音频自动识别生成字幕弹窗
struct GenerateSubtitleSheet: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var library: LibraryManager
    let targetTrack: AudioTrack

    @State private var speechService = SpeechSubtitleService()
    @State private var selectedLocale: SpeechLocaleOption = .enUS
    @State private var preferOnDevice: Bool = true
    @State private var generatedSegments: [AudioSegment] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("目标音频") {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(targetTrack.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("时长 \(TimeFormatters.mmss(targetTrack.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("识别设置") {
                    Picker("口音 / 语言", selection: $selectedLocale) {
                        ForEach(SpeechLocaleOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Toggle("优先本地离线识别", isOn: $preferOnDevice)
                    Text("自动按 45 秒智能切片识别，支持长音频，并结合词级时间戳与标点自动断句，生成后自动保存为 .srt 字幕文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if speechService.isTranscribing {
                    Section("识别进度") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: speechService.progress)
                            Text(speechService.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        Button("取消识别", role: .destructive) {
                            speechService.cancel()
                        }
                    }
                } else {
                    Section {
                        Button {
                            startGeneration()
                        } label: {
                            HStack {
                                Spacer()
                                Label(
                                    generatedSegments.isEmpty ? "开始识别并生成字幕" : "重新识别",
                                    systemImage: "sparkles"
                                )
                                .font(.headline)
                                Spacer()
                            }
                        }
                    }
                }

                if let err = speechService.errorMessage {
                    Section("提示") {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !generatedSegments.isEmpty {
                    Section("识别结果预览（共 \(generatedSegments.count) 句）") {
                        Button {
                            applyGeneratedSubtitles()
                        } label: {
                            HStack {
                                Spacer()
                                Label("保存为 SRT 并应用到播放页", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.blue)

                        ForEach(Array(generatedSegments.enumerated()), id: \.element.id) { idx, seg in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(idx + 1)  \(TimeFormatters.mmssTenth(seg.startTime)) - \(TimeFormatters.mmssTenth(seg.endTime))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(seg.text)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("音频生成字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        speechService.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func startGeneration() {
        let audioURL = library.audioURL(for: targetTrack)
        generatedSegments = []
        Task {
            do {
                let segments = try await speechService.generateSubtitles(
                    audioURL: audioURL,
                    localeIdentifier: selectedLocale.rawValue,
                    preferOnDevice: preferOnDevice
                )
                self.generatedSegments = segments
            } catch {
                // 错误已展示在 speechService.errorMessage 中
            }
        }
    }

    private func applyGeneratedSubtitles() {
        guard !generatedSegments.isEmpty else { return }
        if let updated = library.saveGeneratedSubtitles(segments: generatedSegments, for: targetTrack.id) {
            engine.loadTrack(updated, jumpToSegment: 0, autoPlay: false)
            engine.repeatMode = .subtitle
            engine.showToast("已保存并应用 \(generatedSegments.count) 句字幕")
        }
        dismiss()
    }
}
