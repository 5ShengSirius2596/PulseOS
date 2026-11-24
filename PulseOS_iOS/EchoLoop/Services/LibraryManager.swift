import AVFoundation
import Foundation
import Observation

/// 本地音频库管理：支持导入音频与字幕、合集分类、收藏汇总，以及首次启动自动生成内置英语示范课程
@MainActor
@Observable
final class LibraryManager {
    var tracks: [AudioTrack] = []
    var collections: [String] = ["默认合集", "口语精听", "新闻听力"]

    private let fileManager = FileManager.default
    private var speechSynthesizer: AVSpeechSynthesizer?

    private var libraryDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("AudioLibrary", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var metadataURL: URL {
        libraryDirectory.appendingPathComponent("library_metadata.json")
    }

    init() {
        loadMetadata()
    }

    func audioURL(for track: AudioTrack) -> URL {
        libraryDirectory.appendingPathComponent(track.audioFileName)
    }

    func subtitleURL(fileName: String) -> URL {
        libraryDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Persistence

    func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([AudioTrack].self, from: data) else {
            tracks = []
            return
        }
        tracks = decoded.map { item in
            var copy = item
            copy.refreshTodayIfNeeded()
            return copy
        }
        syncCollections()
    }

    func saveMetadata() {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: metadataURL, options: .atomic)
        }
        syncCollections()
    }

    func updateTrack(_ track: AudioTrack) {
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx] = track
            saveMetadata()
        }
    }

    func deleteTrack(_ track: AudioTrack) {
        let aURL = audioURL(for: track)
        try? fileManager.removeItem(at: aURL)
        if let sub = track.subtitleFileName {
            try? fileManager.removeItem(at: subtitleURL(fileName: sub))
        }
        tracks.removeAll { $0.id == track.id }
        saveMetadata()
    }

    func addCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collections.contains(trimmed) else { return }
        collections.append(trimmed)
    }

    private func syncCollections() {
        var set = Set(collections)
        for t in tracks {
            set.insert(t.collectionName)
        }
        collections = Array(set).sorted()
    }

    // MARK: - Study Statistics & Favorites

    var totalTodayStudySeconds: TimeInterval {
        tracks.reduce(0) { $0 + $1.todayStudySeconds }
    }

    var totalAllTimeStudySeconds: TimeInterval {
        tracks.reduce(0) { $0 + $1.totalStudySeconds }
    }

    struct FavoriteItem: Identifiable {
        let id: UUID
        let track: AudioTrack
        let segmentIndex: Int
        let segment: AudioSegment
    }

    var allFavoriteSegments: [FavoriteItem] {
        var result: [FavoriteItem] = []
        for track in tracks {
            for (idx, seg) in track.segments.enumerated() where seg.isFavorite {
                result.append(FavoriteItem(id: seg.id, track: track, segmentIndex: idx, segment: seg))
            }
        }
        return result
    }

    // MARK: - File Import

    func importAudioFile(from sourceURL: URL, collection: String = "默认合集") throws -> AudioTrack {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let originalName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let uniqueName = "\(UUID().uuidString.prefix(8))_\(originalName)"
        let destURL = libraryDirectory.appendingPathComponent(uniqueName)
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let player = try? AVAudioPlayer(contentsOf: destURL)
        let dur = player?.duration ?? 0

        let track = AudioTrack(
            title: originalName,
            audioFileName: uniqueName,
            subtitleFileName: nil,
            duration: dur,
            collectionName: collection
        )
        tracks.insert(track, at: 0)
        saveMetadata()
        _ = ext
        return track
    }

    func attachSubtitleFile(from sourceURL: URL, to trackID: UUID) throws -> AudioTrack? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        let uniqueName = "\(UUID().uuidString.prefix(8))_\(sourceURL.lastPathComponent)"
        let destURL = libraryDirectory.appendingPathComponent(uniqueName)
        try fileManager.copyItem(at: sourceURL, to: destURL)

        tracks[idx].subtitleFileName = uniqueName
        let cues = SubtitleParser.parse(url: destURL, audioDuration: tracks[idx].duration)
        if !cues.isEmpty {
            tracks[idx].segments = SubtitleParser.convertToSegments(cues: cues)
        }
        saveMetadata()
        return tracks[idx]
    }

    /// 将语音识别生成的字幕保存为 .srt 文件并绑定到指定音频
    func saveGeneratedSubtitles(segments: [AudioSegment], for trackID: UUID) -> AudioTrack? {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        let baseName = (tracks[idx].title as NSString).deletingPathExtension
        let uniqueName = "\(UUID().uuidString.prefix(8))_\(baseName)_auto.srt"
        let destURL = subtitleURL(fileName: uniqueName)
        let srtText = SubtitleParser.exportSRT(segments: segments)
        try? srtText.write(to: destURL, atomically: true, encoding: .utf8)

        tracks[idx].subtitleFileName = uniqueName
        tracks[idx].segments = segments
        tracks[idx].lastSegmentIndex = 0
        saveMetadata()
        return tracks[idx]
    }

    // MARK: - Built-in Demo Lesson Generator (开箱即用，方便首次体验与 App Store 审核)

    func ensureDemoTrackExists() async -> AudioTrack? {
        if let existing = tracks.first {
            return existing
        }

        let audioName = "Demo_Do_you_wanna_take_a_class.wav"
        let subName = "Demo_Do_you_wanna_take_a_class.srt"
        let audioDest = libraryDirectory.appendingPathComponent(audioName)
        let subDest = libraryDirectory.appendingPathComponent(subName)

        let demoLines: [(String, String)] = [
            ("Hey, do you wanna take a class with me this weekend?", "嘿，这周末你想和我一起去上课吗？"),
            ("Sure! What kind of class are you thinking about?", "当然！你在考虑上什么类型的课？"),
            ("I found a great conversational English workshop downtown.", "我在市中心找到一个很棒的英语口语工作坊。"),
            ("That sounds really useful for practicing pronunciation.", "听起来对练习发音非常有用。"),
            ("Each session focuses on listening, shadowing, and real dialogue.", "每节课都会聚焦于听力、跟读和真实对话。"),
            ("Count me in! Let's sign up before the seats fill up.", "算我一个！趁名额还没满我们赶紧报名吧。")
        ]

        // 尝试使用系统离线 AVSpeechSynthesizer 合成真实英语示范音频
        let generated = await synthesizeDemoWAV(lines: demoLines, to: audioDest)
        var builtSegments: [AudioSegment] = []

        if generated.success, !generated.segments.isEmpty {
            builtSegments = generated.segments
        } else {
            // 若在无语音包的模拟器环境，生成带清晰停顿的示范波形 WAV，保证不崩溃且可完整体验断句
            let fallbackDur = generateFallbackDemoWAV(sentenceCount: demoLines.count, to: audioDest)
            let perSeg = fallbackDur / Double(demoLines.count)
            for (i, pair) in demoLines.enumerated() {
                builtSegments.append(
                    AudioSegment(
                        startTime: Double(i) * perSeg,
                        endTime: Double(i + 1) * perSeg,
                        text: pair.0,
                        translation: pair.1
                    )
                )
            }
        }

        let srtContent = SubtitleParser.exportSRT(segments: builtSegments)
        try? srtContent.write(to: subDest, atomically: true, encoding: .utf8)

        let totalDur = builtSegments.last?.endTime ?? (try? AVAudioPlayer(contentsOf: audioDest).duration) ?? 18.0
        let track = AudioTrack(
            title: "38. Do you wanna take a class.wav",
            audioFileName: audioName,
            subtitleFileName: subName,
            duration: totalDur,
            collectionName: "口语精听",
            segments: builtSegments
        )
        tracks.append(track)
        saveMetadata()
        return track
    }

    private func synthesizeDemoWAV(
        lines: [(String, String)],
        to url: URL
    ) async -> (success: Bool, segments: [AudioSegment]) {
        let synth = AVSpeechSynthesizer()
        self.speechSynthesizer = synth
        defer { self.speechSynthesizer = nil }

        var outputFile: AVAudioFile?
        var currentTime: TimeInterval = 0
        var segments: [AudioSegment] = []

        for (en, zh) in lines {
            let utterance = AVSpeechUtterance(string: en)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.47

            let segStart = currentTime
            let writtenFrames: AVAudioFrameCount = await withCheckedContinuation { continuation in
                var framesCount: AVAudioFrameCount = 0
                var didResume = false
                synth.write(utterance) { buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        if !didResume {
                            didResume = true
                            continuation.resume(returning: framesCount)
                        }
                        return
                    }
                    do {
                        if outputFile == nil {
                            outputFile = try AVAudioFile(
                                forWriting: url,
                                settings: pcm.format.settings,
                                commonFormat: pcm.format.commonFormat,
                                interleaved: pcm.format.isInterleaved
                            )
                        }
                        try outputFile?.write(from: pcm)
                        framesCount += pcm.frameLength
                    } catch {
                        // 忽略单帧错误
                    }
                }
            }

            guard let file = outputFile, writtenFrames > 0 else {
                return (false, [])
            }

            let sampleRate = file.processingFormat.sampleRate
            let speechDur = Double(writtenFrames) / sampleRate
            currentTime += speechDur

            // 在句尾插入 0.55 秒静音，让智能断句也能精准识别停顿
            let silenceFrames = AVAudioFrameCount(sampleRate * 0.55)
            if let silenceBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: silenceFrames) {
                silenceBuf.frameLength = silenceFrames
                try? file.write(from: silenceBuf)
                currentTime += 0.55
            }

            segments.append(
                AudioSegment(
                    startTime: segStart,
                    endTime: currentTime,
                    text: en,
                    translation: zh
                )
            )
        }

        return (!segments.isEmpty, segments)
    }

    private func generateFallbackDemoWAV(sentenceCount: Int, to url: URL) -> TimeInterval {
        let sampleRate: Double = 22050
        let toneSec: Double = 2.0
        let silenceSec: Double = 0.6
        let totalSec = Double(sentenceCount) * (toneSec + silenceSec)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            return totalSec
        }
        let chunkFrames = AVAudioFrameCount(sampleRate * (toneSec + silenceSec))
        let toneFrames = Int(sampleRate * toneSec)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return totalSec
        }
        buf.frameLength = chunkFrames
        let ptr = buf.floatChannelData![0]

        for s in 0..<sentenceCount {
            let baseFreq = 260.0 + Double(s) * 35.0
            for i in 0..<Int(chunkFrames) {
                if i < toneFrames {
                    let t = Double(i) / sampleRate
                    let env = sin(.pi * Double(i) / Double(toneFrames)) * (0.65 + 0.35 * sin(2 * .pi * 4.0 * t))
                    ptr[i] = Float(0.25 * env * sin(2 * .pi * baseFreq * t))
                } else {
                    ptr[i] = 0
                }
            }
            try? file.write(from: buf)
        }
        return totalSec
    }
}
