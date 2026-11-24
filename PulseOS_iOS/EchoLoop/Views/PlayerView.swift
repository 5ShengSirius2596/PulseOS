import SwiftUI

/// 主复读播放界面：融合 Apple 原生磨砂卡片美学与一心复读机高效精听交互（自适应浅色/深色模式）
struct PlayerView: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var library: LibraryManager
    @Bindable var settings: AppSettings

    @State private var showSegmentList = false
    @State private var showShadowingSheet = false
    @State private var showMoreSheet = false
    @State private var lookupWord: LookupWordItem?
    @State private var showExportAlert = false
    @State private var showGenerateSubtitleSheet = false
    @State private var exportedSRTText = ""
    @State private var hapticTick: Int = 0

    private let brandBlue = Color(red: 0.13, green: 0.57, blue: 0.96)
    private let brandIndigo = Color(red: 0.44, green: 0.38, blue: 0.92)

    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandBlue, brandIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            // 顶部柔和品牌光晕
            LinearGradient(
                colors: [brandBlue.opacity(0.10), brandIndigo.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .ignoresSafeArea()

            VStack(spacing: 12) {
                headerSection
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                // 字幕精听卡片（支持点按查词与一键生成字幕）
                subtitleStageCard
                    .padding(.horizontal, 16)

                // 波形与 AB 进度一体化卡片
                waveformAndProgressCard
                    .padding(.horizontal, 16)

                // 模式切换胶囊栏
                modeSelectorBar
                    .padding(.horizontal, 16)

                // 微调与段落编辑触控区
                fineTuneAndEditCard
                    .padding(.horizontal, 16)

                // 底部主控播放栏
                transportControlBar
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }

            if let message = engine.statusMessage {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.78), in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if engine.isAnalyzing {
                ProgressView("正在分析波形与断句...")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: engine.statusMessage)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTick)
        .sheet(isPresented: $showSegmentList) {
            SegmentListSheet(engine: engine)
        }
        .sheet(isPresented: $showShadowingSheet) {
            ShadowingSheetView(engine: engine)
        }
        .sheet(isPresented: $showMoreSheet) {
            PlayerMoreSettingsSheet(engine: engine, settings: settings)
        }
        .sheet(isPresented: $showGenerateSubtitleSheet) {
            if let track = engine.currentTrack {
                GenerateSubtitleSheet(engine: engine, library: library, targetTrack: track)
            }
        }
        .sheet(item: $lookupWord) { item in
            DictionaryLookupView(term: item.word)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showExportAlert) {
            NavigationStack {
                ScrollView {
                    Text(exportedSRTText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("导出 SRT 字幕")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: exportedSRTText) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { showExportAlert = false }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("回声复读")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Button {
                        showSegmentList = true
                    } label: {
                        Text("\(engine.segments.isEmpty ? 0 : engine.currentSegmentIndex + 1) / \(engine.segments.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(brandGradient, in: Capsule())
                    }

                    if engine.favoritesOnlyMode {
                        Label("仅收藏", systemImage: "heart.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.pink.opacity(0.14), in: Capsule())
                    }
                }

                Spacer()

                Menu {
                    Button {
                        engine.pause()
                        showGenerateSubtitleSheet = true
                    } label: {
                        Label("语音识别生成字幕", systemImage: "sparkles")
                    }
                    .disabled(engine.currentTrack == nil)

                    Button {
                        engine.reRunSmartSegmentation()
                    } label: {
                        Label("重新智能断句", systemImage: "waveform.badge.magnifyingglass")
                    }

                    Button {
                        engine.favoritesOnlyMode.toggle()
                        engine.showToast(engine.favoritesOnlyMode ? "已开启：仅播收藏段" : "已关闭：仅播收藏段")
                    } label: {
                        Label(engine.favoritesOnlyMode ? "关闭仅播收藏段" : "仅播收藏段", systemImage: "heart.circle")
                    }

                    Button {
                        settings.showSubtitles.toggle()
                    } label: {
                        Label(settings.showSubtitles ? "隐藏字幕（盲听）" : "显示字幕", systemImage: "captions.bubble")
                    }

                    Button {
                        exportedSRTText = SubtitleParser.exportSRT(segments: engine.segments)
                        showExportAlert = true
                    } label: {
                        Label("导出当前断句为 SRT", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(brandIndigo)
                }
            }

            Text(engine.currentTrack?.title ?? "尚未加载音频，请在「文件」页导入")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Subtitle Stage Card

    private var subtitleStageCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 4)
            if settings.showSubtitles, let seg = engine.currentSegment, !seg.text.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        TappableSentenceView(sentence: seg.text) { word in
                            lookupWord = LookupWordItem(word: word)
                        }
                        if settings.showTranslation && !seg.translation.isEmpty {
                            Text(seg.translation)
                                .font(.system(size: 14.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Text("点按任意英文单词即可离线查词")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if !settings.showSubtitles {
                VStack(spacing: 6) {
                    Image(systemName: "ear.and.waveform")
                        .font(.title2)
                        .foregroundStyle(brandIndigo.opacity(0.6))
                    Text("盲听精听模式（已隐藏字幕）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    Text("当前音频无字幕 · 可按波形智能断句复读")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if engine.currentTrack != nil {
                        Button {
                            engine.pause()
                            showGenerateSubtitleSheet = true
                        } label: {
                            Label("从音频自动生成英文字幕", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(brandGradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
    }

    // MARK: - Waveform + AB Progress + Study Stats Card

    private var waveformAndProgressCard: some View {
        VStack(spacing: 10) {
            WaveformTimelineView(
                samples: engine.waveformSamples,
                sampleRateHz: engine.waveformRateHz,
                duration: engine.duration,
                currentTime: engine.currentTime,
                activeStart: engine.activeRange.start,
                activeEnd: engine.activeRange.end,
                segments: engine.segments,
                onSeek: { engine.seek(to: $0) }
            )

            // AB 进度条
            HStack(spacing: 8) {
                Text(TimeFormatters.mmssTenth(engine.currentTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 54, alignment: .leading)

                GeometryReader { geo in
                    let w = max(1, geo.size.width)
                    let dur = max(0.1, engine.duration)
                    let aRatio = CGFloat(max(0, min(1, engine.activeRange.start / dur)))
                    let bRatio = CGFloat(max(aRatio, min(1, engine.activeRange.end / dur)))
                    let curRatio = CGFloat(max(0, min(1, engine.currentTime / dur)))

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 5)

                        Capsule()
                            .fill(brandGradient)
                            .frame(width: max(5, w * (bRatio - aRatio)), height: 5)
                            .offset(x: w * aRatio)

                        Circle()
                            .fill(brandBlue)
                            .frame(width: 13, height: 13)
                            .shadow(color: brandBlue.opacity(0.35), radius: 3)
                            .offset(x: w * curRatio - 6.5)
                    }
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let r = max(0, min(1, value.location.x / w))
                                engine.seek(to: Double(r) * dur)
                            }
                    )
                }
                .frame(height: 18)

                Text(TimeFormatters.mmssTenth(engine.duration))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }

            // A/B 端点标签 + 循环次数 + 学习计时 + 收藏
            HStack(spacing: 8) {
                Menu {
                    ForEach(AppSettings.repeatCountOptions, id: \.self) { count in
                        Button {
                            engine.targetRepeatCount = count
                            engine.currentRepeatPass = 1
                            settings.defaultRepeatCount = count
                        } label: {
                            Text(count == 0 ? "无限循环 (∞)" : "每句复读 \(count) 遍")
                        }
                    }
                } label: {
                    let targetText = engine.effectiveTargetRepeats == 0 ? "∞" : "\(engine.effectiveTargetRepeats)"
                    HStack(spacing: 3) {
                        Image(systemName: "repeat")
                            .font(.caption2.bold())
                        Text("\(engine.currentRepeatPass)/\(targetText)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(brandBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(brandBlue.opacity(0.12), in: Capsule())
                }

                Button {
                    engine.repeatOnceOnly.toggle()
                    hapticTick += 1
                } label: {
                    Text(engine.repeatOnceOnly ? "只复读1次" : "循环中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(engine.repeatOnceOnly ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            engine.repeatOnceOnly ? brandIndigo : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("A \(TimeFormatters.mmssTenth(engine.activeRange.start)) · B \(TimeFormatters.mmssTenth(engine.activeRange.end))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(brandIndigo)
                    Text("今日 \(TimeFormatters.hhmmss(engine.todayStudySeconds)) · 累计 \(TimeFormatters.hhmmss(engine.totalStudySeconds))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    engine.toggleFavoriteCurrentSegment()
                    hapticTick += 1
                } label: {
                    Image(systemName: engine.isCurrentSegmentFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(engine.isCurrentSegmentFavorite ? .pink : .secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            (engine.isCurrentSegmentFavorite ? Color.pink.opacity(0.14) : Color(.tertiarySystemFill)),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
    }

    // MARK: - Mode Segmented Bar

    private var modeSelectorBar: some View {
        HStack(spacing: 6) {
            ForEach(RepeatMode.allCases) { mode in
                let isSelected = engine.repeatMode == mode
                Button {
                    engine.switchMode(mode)
                    hapticTick += 1
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule().fill(brandGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    // MARK: - Fine-Tune & Segment Editing Card

    private var fineTuneAndEditCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                fineTuneTile(letter: "A", directionLeft: true, title: "A 左移") {
                    engine.nudgeA(delta: -settings.fineTuneStep)
                    hapticTick += 1
                }
                fineTuneTile(letter: "A", directionLeft: false, title: "A 右移") {
                    engine.nudgeA(delta: settings.fineTuneStep)
                    hapticTick += 1
                }
                fineTuneTile(letter: "B", directionLeft: true, title: "B 左移") {
                    engine.nudgeB(delta: -settings.fineTuneStep)
                    hapticTick += 1
                }
                fineTuneTile(letter: "B", directionLeft: false, title: "B 右移") {
                    engine.nudgeB(delta: settings.fineTuneStep)
                    hapticTick += 1
                }
                Button {
                    showMoreSheet = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(brandIndigo)
                            .frame(height: 22)
                        Text("更多")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                editActionTile(icon: "scissors", title: "分割", isLongPress: false) {
                    engine.splitCurrentSegment()
                    hapticTick += 1
                }
                editActionTile(icon: "link", title: "合并(长按)", isLongPress: true) {
                    engine.mergeWithNextSegment()
                    hapticTick += 1
                }
                editActionTile(icon: "plus.circle", title: "插入段", isLongPress: false) {
                    engine.insertSegmentAfterCurrent()
                    hapticTick += 1
                }
                editActionTile(icon: "minus.circle", title: "移除(长按)", isLongPress: true) {
                    engine.removeCurrentSegment()
                    hapticTick += 1
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
    }

    private func fineTuneTile(letter: String, directionLeft: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: directionLeft ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(letter)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(brandBlue)
                .frame(height: 22)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func editActionTile(icon: String, title: String, isLongPress: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(brandIndigo)
                .frame(height: 20)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isLongPress {
                engine.showToast("请长按「\(title.replacingOccurrences(of: "(长按)", with: ""))」以防误操作")
            } else {
                action()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            if isLongPress {
                action()
            }
        }
    }

    // MARK: - Bottom Transport Bar

    private var transportControlBar: some View {
        HStack {
            Button {
                engine.pause()
                showShadowingSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(brandBlue)
                        .frame(width: 40, height: 40)
                        .background(brandBlue.opacity(0.12), in: Circle())
                    Text("跟读")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                engine.previousSegment()
                hapticTick += 1
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                    Text("上一句")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // 主播放大按钮（品牌渐变圆形）
            Button {
                engine.togglePlayPause()
                hapticTick += 1
            } label: {
                ZStack {
                    Circle()
                        .fill(brandGradient)
                        .frame(width: 60, height: 60)
                        .shadow(color: brandBlue.opacity(0.35), radius: 10, y: 5)
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: engine.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                engine.nextSegment()
                hapticTick += 1
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                    Text("下一句")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Menu {
                ForEach(AppSettings.speedOptions, id: \.self) { rate in
                    Button {
                        engine.setPlaybackRate(rate)
                    } label: {
                        HStack {
                            Text(String(format: "x%.2g", rate))
                            if abs(engine.playbackRate - rate) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Text(String(format: "%.1fx", engine.playbackRate))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(brandIndigo)
                        .frame(width: 44, height: 40)
                        .background(brandIndigo.opacity(0.12), in: Circle())
                    Text("倍速")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 可点按取词的英文句子视图

struct TappableSentenceView: View {
    let sentence: String
    let onTapWord: (String) -> Void

    private var words: [String] {
        sentence.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var body: some View {
        FlowWordLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, token in
                Button {
                    let cleaned = token.trimmingCharacters(in: CharacterSet.letters.inverted)
                    if !cleaned.isEmpty {
                        onTapWord(cleaned)
                    }
                } label: {
                    Text(token)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowWordLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > bounds.width && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append((subview, size))
            currentRowWidth += size.width + spacing
        }

        var y = bounds.minY
        for row in rows {
            let totalW = row.reduce(0) { $0 + $1.1.width } + CGFloat(max(0, row.count - 1)) * spacing
            var x = bounds.minX + max(0, (bounds.width - totalW) / 2.0)
            let rowH = row.map(\.1.height).max() ?? 0

            for (subview, size) in row {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowH + lineSpacing
        }
    }
}

// MARK: - 段落总览抽屉

struct SegmentListSheet: View {
    @Bindable var engine: AudioPlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(engine.segments.enumerated()), id: \.element.id) { index, seg in
                    Button {
                        engine.selectSegment(at: index, autoPlay: true)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(index == engine.currentSegmentIndex ? .white : .secondary)
                                .frame(width: 26, height: 26)
                                .background(
                                    index == engine.currentSegmentIndex ? Color.blue : Color.gray.opacity(0.15),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(TimeFormatters.mmssTenth(seg.startTime)) - \(TimeFormatters.mmssTenth(seg.endTime))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if !seg.text.isEmpty {
                                    Text(seg.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                if !seg.translation.isEmpty {
                                    Text(seg.translation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if seg.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                }
            }
            .navigationTitle("全部段落 (\(engine.segments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 更多微调与断句灵敏度面板

struct PlayerMoreSettingsSheet: View {
    @Bindable var engine: AudioPlayerEngine
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AB 微调步长") {
                    Picker("每次微调", selection: $settings.fineTuneStep) {
                        ForEach(AppSettings.fineTuneOptions, id: \.self) { step in
                            Text(String(format: "%.2f 秒", step)).tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("复读行为") {
                    Toggle("复读完成后自动进入下一句", isOn: $settings.autoAdvanceAfterRepeat)
                    Toggle("仅播放已收藏段落", isOn: $engine.favoritesOnlyMode)
                    HStack {
                        Text("句间停顿")
                        Spacer()
                        Text(String(format: "%.2f 秒", settings.pauseBetweenRepeats))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.pauseBetweenRepeats, in: 0...2.0, step: 0.05)
                }

                Section("智能断句灵敏度") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("静音检测阈值")
                            Spacer()
                            Text("\(Int(settings.silenceThresholdDB)) dB")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.silenceThresholdDB, in: -50 ... -20, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("最短停顿时长")
                            Spacer()
                            Text(String(format: "%.2f 秒", settings.minSilenceDuration))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.minSilenceDuration, in: 0.15...1.0, step: 0.05)
                    }
                    Button("应用参数并重新智能断句") {
                        engine.reRunSmartSegmentation()
                        dismiss()
                    }
                }
            }
            .navigationTitle("复读与断句设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
