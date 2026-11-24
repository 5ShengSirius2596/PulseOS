import SwiftUI

/// 「我的」页面：渐变学习仪表盘、收藏句库一键跳转复读、默认复读参数与隐私说明
struct ProfileView: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var library: LibraryManager
    @Bindable var settings: AppSettings
    @Binding var selectedTab: Int

    private let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.57, blue: 0.96),
            Color(red: 0.44, green: 0.38, blue: 0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationStack {
            List {
                // 品牌渐变学习统计卡片
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("精听学习概览", systemImage: "waveform.path.ecg")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Spacer()
                            Text("EchoLoop")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        HStack(spacing: 0) {
                            heroStatItem(
                                title: "今日精听",
                                value: TimeFormatters.hhmmss(library.totalTodayStudySeconds)
                            )
                            heroStatItem(
                                title: "累计精听",
                                value: TimeFormatters.hhmmss(library.totalAllTimeStudySeconds)
                            )
                            heroStatItem(
                                title: "收藏难点句",
                                value: "\(library.allFavoriteSegments.count) 句"
                            )
                        }
                    }
                    .padding(16)
                    .background(brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                // 收藏句库
                Section("收藏的难点句") {
                    let favorites = library.allFavoriteSegments
                    if favorites.isEmpty {
                        Text("在播放页点击爱心即可保存重难点句子，方便集中攻坚。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites.prefix(15)) { item in
                            Button {
                                engine.loadTrack(item.track, jumpToSegment: item.segmentIndex, autoPlay: true)
                                selectedTab = 0
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.segment.text.isEmpty ? "第 \(item.segmentIndex + 1) 句 (\(TimeFormatters.mmssTenth(item.segment.startTime)))" : item.segment.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("\(item.track.title) · \(TimeFormatters.mmssTenth(item.segment.startTime)) - \(TimeFormatters.mmssTenth(item.segment.endTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // 复读偏好
                Section("默认复读参数") {
                    Picker("单句默认循环次数", selection: $settings.defaultRepeatCount) {
                        ForEach(AppSettings.repeatCountOptions, id: \.self) { count in
                            Text(count == 0 ? "无限循环" : "\(count) 遍").tag(count)
                        }
                    }
                    Picker("A/B 微调步长", selection: $settings.fineTuneStep) {
                        ForEach(AppSettings.fineTuneOptions, id: \.self) { step in
                            Text(String(format: "%.2f 秒", step)).tag(step)
                        }
                    }
                    Toggle("达到次数后自动下一句", isOn: $settings.autoAdvanceAfterRepeat)
                    Toggle("显示字幕文本", isOn: $settings.showSubtitles)
                    Toggle("显示双语中文翻译", isOn: $settings.showTranslation)
                }

                // 隐私与关于
                Section("隐私与关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本地隐私承诺")
                            .font(.subheadline.weight(.medium))
                        Text("回声复读所有音频文件、字幕解析、智能断句分析、语音识别（离线优先）与录音跟读均优先在您的设备本地完成，不收集、不上传任何个人数据。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("我的")
        }
    }

    private func heroStatItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
    }
}
