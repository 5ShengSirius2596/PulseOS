import AVFoundation
import Foundation
import Observation
import Speech

/// 支持的语音识别语言
enum SpeechLocaleOption: String, CaseIterable, Identifiable {
    case enUS = "en-US"
    case enGB = "en-GB"
    case enAU = "en-AU"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enUS: return "美式英语 (en-US)"
        case .enGB: return "英式英语 (en-GB)"
        case .enAU: return "澳式英语 (en-AU)"
        }
    }
}

/// 基于 Apple 原生 Speech 框架的离线/云端音频转字幕服务
/// 采用智能分段切片识别策略，突破单次 60 秒识别上限，并利用词级时间戳自动按标点与停顿切句
@MainActor
@Observable
final class SpeechSubtitleService {
    var isTranscribing: Bool = false
    var progress: Double = 0
    var statusText: String = ""
    var errorMessage: String?

    private var activeTask: Task<[AudioSegment], Error>?

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isTranscribing = false
        statusText = "已取消"
    }

    /// 读取音频并生成带精确时间戳的英文字幕段落
    func generateSubtitles(
        audioURL: URL,
        localeIdentifier: String = "en-US",
        preferOnDevice: Bool = true
    ) async throws -> [AudioSegment] {
        errorMessage = nil
        progress = 0
        statusText = "正在请求语音识别权限..."

        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            let msg = "未获得语音识别权限，请在系统「设置 -> 隐私与安全性 -> 语音识别」中允许回声复读。"
            errorMessage = msg
            throw NSError(domain: "EchoLoop.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            let msg = "当前语言（\(localeIdentifier)）的语音识别服务暂不可用，请检查网络或下载系统离线语音包。"
            errorMessage = msg
            throw NSError(domain: "EchoLoop.Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let task = Task<[AudioSegment], Error> {
            // 1. 将音频切分为 <= 45 秒的临时 WAV 片段，避免触发 Apple 60 秒单次识别上限
            await MainActor.run {
                self.statusText = "正在切分音频片段..."
                self.progress = 0.05
            }

            let chunks = try await Self.sliceAudioIntoChunks(url: audioURL, maxChunkSeconds: 45.0)
            defer {
                for chunk in chunks {
                    try? FileManager.default.removeItem(at: chunk.url)
                }
            }

            var allSegments: [AudioSegment] = []
            let totalChunks = max(1, chunks.count)

            for (idx, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                await MainActor.run {
                    self.statusText = "正在识别第 \(idx + 1) / \(totalChunks) 段..."
                    self.progress = 0.1 + 0.85 * (Double(idx) / Double(totalChunks))
                }

                let chunkSegments = try await Self.recognizeChunk(
                    url: chunk.url,
                    timeOffset: chunk.startTime,
                    chunkDuration: chunk.duration,
                    recognizer: recognizer,
                    preferOnDevice: preferOnDevice
                )
                allSegments.append(contentsOf: chunkSegments)
            }

            await MainActor.run {
                self.progress = 1.0
                self.statusText = "字幕生成完成，共 \(allSegments.count) 句"
            }
            return allSegments
        }

        activeTask = task
        do {
            let result = try await task.value
            activeTask = nil
            return result
        } catch {
            activeTask = nil
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Authorization

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Chunk Slicing

    private struct AudioChunk: Sendable {
        let url: URL
        let startTime: TimeInterval
        let duration: TimeInterval
    }

    nonisolated private static func sliceAudioIntoChunks(
        url: URL,
        maxChunkSeconds: TimeInterval
    ) async throws -> [AudioChunk] {
        try await Task.detached(priority: .userInitiated) {
            let sourceFile = try AVAudioFile(forReading: url)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            guard totalFrames > 0, sampleRate > 0 else { return [] }

            let framesPerChunk = AVAudioFramePosition(sampleRate * maxChunkSeconds)
            let tempDir = FileManager.default.temporaryDirectory
            var chunks: [AudioChunk] = []
            var position: AVAudioFramePosition = 0
            var chunkIndex = 0

            while position < totalFrames {
                try Task.checkCancellation()
                let remaining = totalFrames - position
                let framesToCopy = AVAudioFrameCount(min(framesPerChunk, remaining))
                let chunkURL = tempDir.appendingPathComponent("echoloop_stt_\(UUID().uuidString)_\(chunkIndex).wav")

                let outFile = try AVAudioFile(
                    forWriting: chunkURL,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )

                sourceFile.framePosition = position
                let bufferSize: AVAudioFrameCount = 32768
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
                    break
                }

                var copied: AVAudioFrameCount = 0
                while copied < framesToCopy {
                    let toRead = min(bufferSize, framesToCopy - copied)
                    try sourceFile.read(into: buffer, frameCount: toRead)
                    if buffer.frameLength == 0 { break }
                    try outFile.write(from: buffer)
                    copied += buffer.frameLength
                }

                let startSec = Double(position) / sampleRate
                let durSec = Double(copied) / sampleRate
                chunks.append(AudioChunk(url: chunkURL, startTime: startSec, duration: durSec))

                position += AVAudioFramePosition(copied)
                chunkIndex += 1
            }

            return chunks
        }.value
    }

    // MARK: - Speech Recognition & Sentence Grouping

    nonisolated private static func recognizeChunk(
        url: URL,
        timeOffset: TimeInterval,
        chunkDuration: TimeInterval,
        recognizer: SFSpeechRecognizer,
        preferOnDevice: Bool
    ) async throws -> [AudioSegment] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let transcription: SFTranscription = try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !didResume {
                        didResume = true
                        task?.cancel()
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let result, result.isFinal {
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: result.bestTranscription)
                    }
                }
            }
        }

        return buildSegments(
            from: transcription,
            timeOffset: timeOffset,
            chunkDuration: chunkDuration
        )
    }

    /// 根据词级时间戳、句末标点与语流停顿将识别结果组织为自然英语句子
    nonisolated private static func buildSegments(
        from transcription: SFTranscription,
        timeOffset: TimeInterval,
        chunkDuration: TimeInterval
    ) -> [AudioSegment] {
        let words = transcription.segments
        guard !words.isEmpty else {
            let trimmed = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            return [
                AudioSegment(
                    startTime: timeOffset,
                    endTime: timeOffset + max(0.5, chunkDuration),
                    text: trimmed
                )
            ]
        }

        var sentences: [AudioSegment] = []
        var bufferWords: [SFTranscriptionSegment] = []

        func flushBuffer() {
            guard let first = bufferWords.first, let last = bufferWords.last else { return }
            let rawText = bufferWords.map(\.substring).joined(separator: " ")
            let cleanedText = cleanSpacingAroundPunctuation(rawText)
            let start = max(0, timeOffset + first.timestamp - 0.08)
            let end = timeOffset + last.timestamp + max(0.25, last.duration) + 0.12
            if !cleanedText.isEmpty {
                sentences.append(
                    AudioSegment(
                        startTime: start,
                        endTime: max(start + 0.3, end),
                        text: cleanedText
                    )
                )
            }
            bufferWords.removeAll(keepingCapacity: true)
        }

        let sentenceEnders: Set<Character> = [".", "?", "!", "。", "？", "！"]

        for (index, word) in words.enumerated() {
            bufferWords.append(word)

            let endsWithPunctuation = word.substring.last.map { sentenceEnders.contains($0) } ?? false
            var hasLongPauseAfter = false
            if index + 1 < words.count {
                let nextWord = words[index + 1]
                let gap = nextWord.timestamp - (word.timestamp + word.duration)
                if gap >= 0.65 {
                    hasLongPauseAfter = true
                }
            }

            let reachedMaxWords = bufferWords.count >= 18
            if endsWithPunctuation || hasLongPauseAfter || reachedMaxWords {
                flushBuffer()
            }
        }

        flushBuffer()
        return sentences
    }

    nonisolated private static func cleanSpacingAroundPunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ;", with: ";")
            .replacingOccurrences(of: " :", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
