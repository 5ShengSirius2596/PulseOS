import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// 核心音频分段复读引擎：负责高精度 AB 循环、变调不变速、段落编辑、学习计时与锁屏/蓝牙遥控
@MainActor
@Observable
final class AudioPlayerEngine: NSObject {
    // MARK: - Published State
    var currentTrack: AudioTrack?
    var segments: [AudioSegment] = []
    var currentSegmentIndex: Int = 0
    var waveformSamples: [Float] = []
    var waveformRateHz: Double = 25.0

    var isPlaying: Bool = false
    var isAnalyzing: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    var repeatMode: RepeatMode = .smart
    var playbackRate: Float = 1.0
    var repeatOnceOnly: Bool = false
    var favoritesOnlyMode: Bool = false

    /// 当前句已复读第几遍（从 1 开始）
    var currentRepeatPass: Int = 1
    /// 当前句目标复读次数（0 表示无限循环）
    var targetRepeatCount: Int = 5

    /// AB 自由模式下的临时 A/B 点
    var abStart: TimeInterval = 0
    var abEnd: TimeInterval = 5

    /// 学习时长显示（秒）
    var todayStudySeconds: TimeInterval = 0
    var totalStudySeconds: TimeInterval = 0

    /// 提示消息（Toast）
    var statusMessage: String?

    // MARK: - Private
    private var player: AVAudioPlayer?
    private var tickTimer: Timer?
    private var pauseTask: Task<Void, Never>?
    private var lastTickDate: Date?
    private var accumulatedUnsavedStudy: TimeInterval = 0
    private var isRemoteConfigured = false

    weak var libraryManager: LibraryManager?
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        self.targetRepeatCount = settings.defaultRepeatCount
        super.init()
        configureAudioSessionForPlayback()
        configureRemoteCommands()
    }

    // MARK: - Computed Properties

    var activeRange: (start: TimeInterval, end: TimeInterval) {
        if repeatMode == .abLoop {
            let s = max(0, min(abStart, duration))
            let e = max(s + 0.2, min(abEnd, duration))
            return (s, e)
        }
        guard segments.indices.contains(currentSegmentIndex) else {
            return (0, max(0.5, duration))
        }
        let seg = segments[currentSegmentIndex]
        return (seg.startTime, seg.endTime)
    }

    var currentSegment: AudioSegment? {
        guard segments.indices.contains(currentSegmentIndex) else { return nil }
        return segments[currentSegmentIndex]
    }

    var isCurrentSegmentFavorite: Bool {
        currentSegment?.isFavorite ?? false
    }

    var effectiveTargetRepeats: Int {
        repeatOnceOnly ? 1 : targetRepeatCount
    }

    // MARK: - Track Loading

    func loadTrack(_ track: AudioTrack, jumpToSegment: Int? = nil, autoPlay: Bool = false) {
        stop()
        guard let library = libraryManager else { return }
        let audioURL = library.audioURL(for: track)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            showToast("找不到音频文件")
            return
        }

        var updatedTrack = track
        updatedTrack.refreshTodayIfNeeded()
        currentTrack = updatedTrack
        todayStudySeconds = updatedTrack.todayStudySeconds
        totalStudySeconds = updatedTrack.totalStudySeconds
        targetRepeatCount = settings.defaultRepeatCount
        currentRepeatPass = 1

        do {
            configureAudioSessionForPlayback()
            let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer.enableRate = true
            audioPlayer.rate = playbackRate
            audioPlayer.prepareToPlay()
            player = audioPlayer
            duration = audioPlayer.duration
        } catch {
            showToast("音频加载失败：\(error.localizedDescription)")
            return
        }

        // 如果有现成段落则直接使用；否则异步提取波形并断句
        let existingSegments = updatedTrack.segments
        isAnalyzing = true
        let threshold = settings.silenceThresholdDB
        let minSilence = settings.minSilenceDuration
        let minSeg = settings.minSegmentDuration
        let subtitleURL = updatedTrack.subtitleFileName.map { library.subtitleURL(fileName: $0) }

        Task {
            do {
                let result = try await AudioAnalysisService.analyzeAudio(
                    url: audioURL,
                    silenceThresholdDB: threshold,
                    minSilenceDuration: minSilence,
                    minSegmentDuration: minSeg
                )
                self.waveformSamples = result.waveformSamples
                self.waveformRateHz = result.sampleRateHz
                self.duration = max(self.duration, result.duration)

                if !existingSegments.isEmpty {
                    self.segments = existingSegments
                } else if let subURL = subtitleURL,
                          FileManager.default.fileExists(atPath: subURL.path) {
                    let cues = SubtitleParser.parse(url: subURL, audioDuration: self.duration)
                    if !cues.isEmpty {
                        self.segments = SubtitleParser.convertToSegments(cues: cues)
                        self.repeatMode = .subtitle
                    } else {
                        self.segments = result.segments
                        self.repeatMode = .smart
                    }
                } else {
                    self.segments = result.segments
                    self.repeatMode = .smart
                }

                let targetIdx = jumpToSegment ?? min(updatedTrack.lastSegmentIndex, max(0, self.segments.count - 1))
                self.currentSegmentIndex = max(0, min(targetIdx, max(0, self.segments.count - 1)))
                self.syncABFromCurrentSegment()
                self.seek(to: self.activeRange.start)
                self.persistCurrentTrackState()
                self.isAnalyzing = false
                self.updateNowPlayingInfo()

                if autoPlay {
                    self.play()
                }
            } catch {
                self.isAnalyzing = false
                self.showToast("波形分析失败")
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        pauseTask?.cancel()
        configureAudioSessionForPlayback()

        let range = activeRange
        if player.currentTime < range.start - 0.05 || player.currentTime >= range.end - 0.05 {
            player.currentTime = range.start
        }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        lastTickDate = Date()
        startTickTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        pauseTask?.cancel()
        player?.pause()
        isPlaying = false
        stopTickTimer()
        flushStudyTime()
        updateNowPlayingInfo()
    }

    func stop() {
        pauseTask?.cancel()
        player?.stop()
        isPlaying = false
        stopTickTimer()
        flushStudyTime()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.currentTime = clamped
        currentTime = clamped
        updateNowPlayingInfo()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        player?.rate = playbackRate
        updateNowPlayingInfo()
    }

    func cyclePlaybackRate(direction: Int) {
        let options = AppSettings.speedOptions
        let currentIdx = options.enumerated().min(by: { abs($0.element - playbackRate) < abs($1.element - playbackRate) })?.offset ?? 4
        let nextIdx = (currentIdx + direction + options.count) % options.count
        setPlaybackRate(options[nextIdx])
    }

    func selectSegment(at index: Int, autoPlay: Bool = true) {
        guard segments.indices.contains(index) else { return }
        pauseTask?.cancel()
        currentSegmentIndex = index
        currentRepeatPass = 1
        syncABFromCurrentSegment()
        seek(to: activeRange.start)
        persistCurrentTrackState()
        if autoPlay {
            play()
        }
    }

    func previousSegment() {
        guard !segments.isEmpty else { return }
        if favoritesOnlyMode {
            let favIndices = segments.indices.filter { segments[$0].isFavorite }
            guard !favIndices.isEmpty else {
                showToast("暂无收藏句")
                return
            }
            if let pos = favIndices.lastIndex(where: { $0 < currentSegmentIndex }) {
                selectSegment(at: favIndices[pos], autoPlay: isPlaying)
            } else if let last = favIndices.last {
                selectSegment(at: last, autoPlay: isPlaying)
            }
            return
        }
        let prev = currentSegmentIndex > 0 ? currentSegmentIndex - 1 : segments.count - 1
        selectSegment(at: prev, autoPlay: isPlaying)
    }

    func nextSegment() {
        guard !segments.isEmpty else { return }
        if favoritesOnlyMode {
            let favIndices = segments.indices.filter { segments[$0].isFavorite }
            guard !favIndices.isEmpty else {
                showToast("暂无收藏句")
                return
            }
            if let pos = favIndices.firstIndex(where: { $0 > currentSegmentIndex }) {
                selectSegment(at: favIndices[pos], autoPlay: isPlaying)
            } else if let first = favIndices.first {
                selectSegment(at: first, autoPlay: isPlaying)
            }
            return
        }
        let next = (currentSegmentIndex + 1) % segments.count
        selectSegment(at: next, autoPlay: isPlaying)
    }

    // MARK: - Mode Switching

    func switchMode(_ mode: RepeatMode) {
        repeatMode = mode
        switch mode {
        case .smart:
            if segments.isEmpty {
                reRunSmartSegmentation()
            } else {
                syncABFromCurrentSegment()
            }
        case .subtitle:
            applySubtitleSegmentation()
        case .abLoop:
            syncABFromCurrentSegment()
            showToast("已切换至 AB 自由复读模式")
        }
    }

    func reRunSmartSegmentation() {
        guard let track = currentTrack, let library = libraryManager else { return }
        let url = library.audioURL(for: track)
        isAnalyzing = true
        let threshold = settings.silenceThresholdDB
        let minSilence = settings.minSilenceDuration
        let minSeg = settings.minSegmentDuration

        Task {
            do {
                let result = try await AudioAnalysisService.analyzeAudio(
                    url: url,
                    silenceThresholdDB: threshold,
                    minSilenceDuration: minSilence,
                    minSegmentDuration: minSeg
                )
                self.segments = result.segments
                self.currentSegmentIndex = 0
                self.currentRepeatPass = 1
                self.syncABFromCurrentSegment()
                self.seek(to: self.activeRange.start)
                self.persistCurrentTrackState()
                self.isAnalyzing = false
                self.showToast("已完成智能断句，共 \(result.segments.count) 句")
            } catch {
                self.isAnalyzing = false
                self.showToast("智能断句失败")
            }
        }
    }

    func applySubtitleSegmentation() {
        guard let track = currentTrack, let library = libraryManager else { return }
        guard let subFile = track.subtitleFileName else {
            showToast("当前音频未绑定字幕，请在「文件」页导入 .srt/.lrc")
            return
        }
        let subURL = library.subtitleURL(fileName: subFile)
        let cues = SubtitleParser.parse(url: subURL, audioDuration: duration)
        guard !cues.isEmpty else {
            showToast("字幕解析为空")
            return
        }
        segments = SubtitleParser.convertToSegments(cues: cues)
        currentSegmentIndex = 0
        currentRepeatPass = 1
        syncABFromCurrentSegment()
        seek(to: activeRange.start)
        persistCurrentTrackState()
        showToast("已按字幕切分，共 \(segments.count) 句")
    }

    // MARK: - Fine-Tuning & Segment Editing (一心复读机核心操作)

    func nudgeA(delta: TimeInterval) {
        if repeatMode == .abLoop {
            let newStart = max(0, min(abStart + delta, abEnd - 0.2))
            abStart = newStart
            seek(to: newStart)
            return
        }
        guard segments.indices.contains(currentSegmentIndex) else { return }
        let currentEnd = segments[currentSegmentIndex].endTime
        let newStart = max(0, min(segments[currentSegmentIndex].startTime + delta, currentEnd - 0.2))
        segments[currentSegmentIndex].startTime = newStart
        if currentSegmentIndex > 0 && segments[currentSegmentIndex - 1].endTime > newStart {
            segments[currentSegmentIndex - 1].endTime = newStart
        }
        syncABFromCurrentSegment()
        seek(to: newStart)
        persistCurrentTrackState()
    }

    func nudgeB(delta: TimeInterval) {
        if repeatMode == .abLoop {
            let newEnd = max(abStart + 0.2, min(abEnd + delta, duration))
            abEnd = newEnd
            seek(to: max(abStart, newEnd - 1.2))
            return
        }
        guard segments.indices.contains(currentSegmentIndex) else { return }
        let currentStart = segments[currentSegmentIndex].startTime
        let newEnd = max(currentStart + 0.2, min(segments[currentSegmentIndex].endTime + delta, duration))
        segments[currentSegmentIndex].endTime = newEnd
        if currentSegmentIndex + 1 < segments.count && segments[currentSegmentIndex + 1].startTime < newEnd {
            segments[currentSegmentIndex + 1].startTime = newEnd
        }
        syncABFromCurrentSegment()
        // 试听句尾 1.2 秒，方便确认断句位置
        seek(to: max(currentStart, newEnd - 1.2))
        persistCurrentTrackState()
    }

    /// 在当前播放位置分割当前句
    func splitCurrentSegment() {
        guard segments.indices.contains(currentSegmentIndex) else { return }
        let seg = segments[currentSegmentIndex]
        var splitPoint = currentTime
        if splitPoint <= seg.startTime + 0.25 || splitPoint >= seg.endTime - 0.25 {
            splitPoint = (seg.startTime + seg.endTime) / 2.0
        }
        guard splitPoint - seg.startTime >= 0.2, seg.endTime - splitPoint >= 0.2 else {
            showToast("当前段落过短，无法分割")
            return
        }

        let firstHalf = AudioSegment(
            startTime: seg.startTime,
            endTime: splitPoint,
            text: seg.text,
            translation: seg.translation,
            isFavorite: seg.isFavorite
        )
        let secondHalf = AudioSegment(
            startTime: splitPoint,
            endTime: seg.endTime,
            text: "",
            translation: "",
            isFavorite: false
        )
        segments.replaceSubrange(currentSegmentIndex...currentSegmentIndex, with: [firstHalf, secondHalf])
        syncABFromCurrentSegment()
        persistCurrentTrackState()
        showToast("已分割为两句")
    }

    /// 合并当前句与下一句（长按触发）
    func mergeWithNextSegment() {
        guard segments.indices.contains(currentSegmentIndex),
              currentSegmentIndex + 1 < segments.count else {
            showToast("已是最后一句，无法向后合并")
            return
        }
        let curr = segments[currentSegmentIndex]
        let next = segments[currentSegmentIndex + 1]
        let combinedText = [curr.text, next.text].filter { !$0.isEmpty }.joined(separator: " ")
        let combinedTrans = [curr.translation, next.translation].filter { !$0.isEmpty }.joined(separator: " ")
        let merged = AudioSegment(
            startTime: curr.startTime,
            endTime: next.endTime,
            text: combinedText,
            translation: combinedTrans,
            isFavorite: curr.isFavorite || next.isFavorite
        )
        segments.replaceSubrange(currentSegmentIndex...(currentSegmentIndex + 1), with: [merged])
        syncABFromCurrentSegment()
        persistCurrentTrackState()
        showToast("已合并相邻段落")
    }

    /// 在当前句之后插入新段
    func insertSegmentAfterCurrent() {
        guard duration > 0.5 else { return }
        if segments.isEmpty {
            segments = [AudioSegment(startTime: 0, endTime: min(5, duration))]
            currentSegmentIndex = 0
            syncABFromCurrentSegment()
            persistCurrentTrackState()
            return
        }
        let idx = min(currentSegmentIndex, segments.count - 1)
        let curr = segments[idx]
        let nextStart = (idx + 1 < segments.count) ? segments[idx + 1].startTime : duration
        let gap = nextStart - curr.endTime

        if gap >= 0.4 {
            let newSeg = AudioSegment(startTime: curr.endTime, endTime: min(nextStart, curr.endTime + 3.0))
            segments.insert(newSeg, at: idx + 1)
            selectSegment(at: idx + 1, autoPlay: isPlaying)
            showToast("已插入新段落")
        } else {
            // 若无空隙，从当前句尾部切出 1/3 作为新段
            let cut = curr.startTime + curr.duration * 0.65
            guard curr.endTime - cut >= 0.25 else {
                showToast("当前区域空间不足，请先调整 B 点")
                return
            }
            segments[idx].endTime = cut
            let newSeg = AudioSegment(startTime: cut, endTime: curr.endTime)
            segments.insert(newSeg, at: idx + 1)
            selectSegment(at: idx + 1, autoPlay: isPlaying)
            showToast("已插入新段落")
        }
    }

    /// 移除当前句（长按触发）
    func removeCurrentSegment() {
        guard segments.count > 1, segments.indices.contains(currentSegmentIndex) else {
            showToast("至少保留一个段落")
            return
        }
        segments.remove(at: currentSegmentIndex)
        currentSegmentIndex = min(currentSegmentIndex, segments.count - 1)
        currentRepeatPass = 1
        syncABFromCurrentSegment()
        seek(to: activeRange.start)
        persistCurrentTrackState()
        showToast("已移除当前段落")
    }

    func toggleFavoriteCurrentSegment() {
        guard segments.indices.contains(currentSegmentIndex) else { return }
        segments[currentSegmentIndex].isFavorite.toggle()
        persistCurrentTrackState()
        showToast(segments[currentSegmentIndex].isFavorite ? "已收藏当前句" : "已取消收藏")
    }

    // MARK: - Private Timer & Loop Logic

    private func startTickTimer() {
        stopTickTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackTick()
            }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
        lastTickDate = nil
    }

    private func handlePlaybackTick() {
        guard let player, isPlaying else { return }

        let now = Date()
        if let last = lastTickDate {
            let delta = min(0.5, now.timeIntervalSince(last))
            todayStudySeconds += delta
            totalStudySeconds += delta
            accumulatedUnsavedStudy += delta
            if accumulatedUnsavedStudy >= 5.0 {
                flushStudyTime()
            }
        }
        lastTickDate = now

        let pos = player.currentTime
        currentTime = pos
        let range = activeRange

        // 检测是否到达段落终点 B
        if pos >= range.end - 0.03 || !player.isPlaying {
            handleReachedSegmentEnd()
        }
    }

    private func handleReachedSegmentEnd() {
        guard let player else { return }
        let target = effectiveTargetRepeats

        if repeatMode == .abLoop || target == 0 || currentRepeatPass < target {
            // 继续复读本句
            if target > 0 {
                currentRepeatPass += 1
            } else {
                currentRepeatPass += 1
            }
            let pauseSec = settings.pauseBetweenRepeats
            if pauseSec > 0.05 {
                player.pause()
                stopTickTimer()
                pauseTask?.cancel()
                pauseTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(pauseSec * 1_000_000_000))
                    guard !Task.isCancelled, self.isPlaying else { return }
                    self.player?.currentTime = self.activeRange.start
                    self.currentTime = self.activeRange.start
                    self.player?.rate = self.playbackRate
                    self.player?.play()
                    self.lastTickDate = Date()
                    self.startTickTimer()
                }
            } else {
                player.currentTime = activeRange.start
                currentTime = activeRange.start
                player.play()
            }
        } else {
            // 达到设定复读次数
            if settings.autoAdvanceAfterRepeat && segments.count > 1 {
                nextSegment()
            } else {
                currentRepeatPass = 1
                pause()
                seek(to: activeRange.start)
            }
        }
    }

    private func syncABFromCurrentSegment() {
        if let seg = currentSegment {
            abStart = seg.startTime
            abEnd = seg.endTime
        }
    }

    private func flushStudyTime() {
        guard accumulatedUnsavedStudy > 0 else { return }
        accumulatedUnsavedStudy = 0
        persistCurrentTrackState()
    }

    private func persistCurrentTrackState() {
        guard var track = currentTrack else { return }
        track.segments = segments
        track.lastSegmentIndex = currentSegmentIndex
        track.todayStudySeconds = todayStudySeconds
        track.totalStudySeconds = totalStudySeconds
        track.lastStudyDayKey = AudioTrack.currentDayKey()
        currentTrack = track
        libraryManager?.updateTrack(track)
    }

    func showToast(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.statusMessage == message {
                self.statusMessage = nil
            }
        }
    }

    // MARK: - Audio Session & Remote Control (锁屏 & 蓝牙耳机控制)

    func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            // 模拟器或无音频路由时安全忽略
        }
    }

    private func configureRemoteCommands() {
        guard !isRemoteConfigured else { return }
        isRemoteConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextSegment() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousSegment() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "回声复读 · 第 \(currentSegmentIndex + 1)/\(max(1, segments.count)) 句",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        if let seg = currentSegment, !seg.text.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = seg.text
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
