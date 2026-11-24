import AVFoundation
import Accelerate
import Foundation

/// 音频波形提取与智能断句（基于能量/静音检测 VAD）
enum AudioAnalysisService {
    struct AnalysisResult: Sendable {
        let duration: TimeInterval
        /// 每秒 25 个归一化波形柱高度 [0, 1]
        let waveformSamples: [Float]
        let sampleRateHz: Double
        let segments: [AudioSegment]
    }

    /// 分析音频文件：提取高分辨率波形并执行智能断句
    nonisolated static func analyzeAudio(
        url: URL,
        silenceThresholdDB: Double = -34.0,
        minSilenceDuration: Double = 0.35,
        minSegmentDuration: Double = 1.2
    ) async throws -> AnalysisResult {
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = AVAudioFrameCount(file.length)
            let duration = Double(totalFrames) / sampleRate

            guard totalFrames > 0, sampleRate > 0 else {
                return AnalysisResult(duration: 0, waveformSamples: [], sampleRateHz: 25, segments: [])
            }

            // 以 40ms 为一帧（每秒 25 帧）计算 RMS 振幅，既足够绘制精细波形又高效完成静音切分
            let framesPerBucket = max(1, Int(sampleRate * 0.04))
            let chunkSize: AVAudioFrameCount = 65536
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return AnalysisResult(duration: duration, waveformSamples: [], sampleRateHz: 25, segments: [])
            }

            var rmsBuckets: [Float] = []
            rmsBuckets.reserveCapacity(Int(duration * 25) + 16)

            var accumulator: Float = 0
            var accumulatedCount: Int = 0

            while file.framePosition < file.length {
                let remaining = AVAudioFrameCount(file.length - file.framePosition)
                let toRead = min(chunkSize, remaining)
                try file.read(into: buffer, frameCount: toRead)
                let count = Int(buffer.frameLength)
                guard count > 0, let channelData = buffer.floatChannelData else { break }

                // 取第 0 声道（或双声道平均）快速计算平方和
                let ch0 = channelData[0]
                var index = 0
                while index < count {
                    let needed = framesPerBucket - accumulatedCount
                    let take = min(needed, count - index)
                    var sumSquares: Float = 0
                    vDSP_svesq(ch0.advanced(by: index), 1, &sumSquares, vDSP_Length(take))
                    accumulator += sumSquares
                    accumulatedCount += take
                    index += take

                    if accumulatedCount >= framesPerBucket {
                        let rms = sqrt(accumulator / Float(accumulatedCount))
                        rmsBuckets.append(rms)
                        accumulator = 0
                        accumulatedCount = 0
                    }
                }
            }

            if accumulatedCount > 0 {
                let rms = sqrt(accumulator / Float(accumulatedCount))
                rmsBuckets.append(rms)
            }

            // 归一化波形（使用 98 分位数防止单点爆音压扁整体波形）
            let normalizedWaveform = normalizeWaveform(rmsBuckets)

            // 智能断句
            let segments = detectSegments(
                rmsBuckets: rmsBuckets,
                bucketDuration: Double(framesPerBucket) / sampleRate,
                totalDuration: duration,
                silenceThresholdDB: silenceThresholdDB,
                minSilenceDuration: minSilenceDuration,
                minSegmentDuration: minSegmentDuration
            )

            return AnalysisResult(
                duration: duration,
                waveformSamples: normalizedWaveform,
                sampleRateHz: sampleRate / Double(framesPerBucket),
                segments: segments
            )
        }.value
    }

    /// 仅提取波形（用于跟读录音波形对比）
    nonisolated static func extractWaveform(url: URL, bucketsPerSecond: Double = 25) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url) else { return [] }
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            guard sampleRate > 0, file.length > 0 else { return [] }

            let framesPerBucket = max(1, Int(sampleRate / bucketsPerSecond))
            let chunkSize: AVAudioFrameCount = 32768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return [] }

            var rmsBuckets: [Float] = []
            var accumulator: Float = 0
            var accumulatedCount: Int = 0

            while file.framePosition < file.length {
                let remaining = AVAudioFrameCount(file.length - file.framePosition)
                let toRead = min(chunkSize, remaining)
                guard (try? file.read(into: buffer, frameCount: toRead)) != nil else { break }
                let count = Int(buffer.frameLength)
                guard count > 0, let ch0 = buffer.floatChannelData?[0] else { break }

                var index = 0
                while index < count {
                    let take = min(framesPerBucket - accumulatedCount, count - index)
                    var sumSquares: Float = 0
                    vDSP_svesq(ch0.advanced(by: index), 1, &sumSquares, vDSP_Length(take))
                    accumulator += sumSquares
                    accumulatedCount += take
                    index += take

                    if accumulatedCount >= framesPerBucket {
                        rmsBuckets.append(sqrt(accumulator / Float(accumulatedCount)))
                        accumulator = 0
                        accumulatedCount = 0
                    }
                }
            }
            if accumulatedCount > 0 {
                rmsBuckets.append(sqrt(accumulator / Float(accumulatedCount)))
            }
            return normalizeWaveform(rmsBuckets)
        }.value
    }

    // MARK: - Internal DSP Helpers

    nonisolated private static func normalizeWaveform(_ rms: [Float]) -> [Float] {
        guard !rms.isEmpty else { return [] }
        let sorted = rms.sorted()
        let p98Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.98))
        let peak = max(sorted[p98Index], 0.001)
        return rms.map { value in
            let scaled = min(1.0, value / peak)
            // 轻微开方增强弱音细节，类似专业音频波形视图
            return pow(scaled, 0.72)
        }
    }

    nonisolated private static func detectSegments(
        rmsBuckets: [Float],
        bucketDuration: Double,
        totalDuration: TimeInterval,
        silenceThresholdDB: Double,
        minSilenceDuration: Double,
        minSegmentDuration: Double
    ) -> [AudioSegment] {
        guard !rmsBuckets.isEmpty, totalDuration > 0.2 else {
            return [AudioSegment(startTime: 0, endTime: max(0.5, totalDuration))]
        }

        // 将 dB 阈值转换为线性振幅，同时结合文件自身峰值自适应避免录音音量偏小导致全部判为静音
        let linearFloor = Float(pow(10.0, silenceThresholdDB / 20.0))
        let sorted = rmsBuckets.sorted()
        let peak = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let adaptiveThreshold = min(linearFloor, peak * 0.14)
        let threshold = max(0.002, adaptiveThreshold)

        let minSilenceBuckets = max(2, Int((minSilenceDuration / bucketDuration).rounded()))

        // 找出所有连续静音区间
        var silenceMidpoints: [TimeInterval] = []
        var silentRun = 0
        var runStartIndex = 0

        for (i, rms) in rmsBuckets.enumerated() {
            if rms < threshold {
                if silentRun == 0 { runStartIndex = i }
                silentRun += 1
            } else {
                if silentRun >= minSilenceBuckets {
                    let midBucket = Double(runStartIndex) + Double(silentRun) / 2.0
                    let midTime = midBucket * bucketDuration
                    if midTime > 0.3 && midTime < totalDuration - 0.3 {
                        silenceMidpoints.append(midTime)
                    }
                }
                silentRun = 0
            }
        }

        // 根据静音切点组装句子，并合并过短段落
        var cutPoints: [TimeInterval] = [0]
        for point in silenceMidpoints {
            if let last = cutPoints.last, point - last >= minSegmentDuration {
                cutPoints.append(point)
            }
        }
        if let last = cutPoints.last, totalDuration - last < minSegmentDuration * 0.6, cutPoints.count > 1 {
            cutPoints[cutPoints.count - 1] = totalDuration
        } else {
            cutPoints.append(totalDuration)
        }

        var segments: [AudioSegment] = []
        for idx in 0..<(cutPoints.count - 1) {
            let start = cutPoints[idx]
            let end = cutPoints[idx + 1]
            if end - start >= 0.2 {
                segments.append(AudioSegment(startTime: start, endTime: end))
            }
        }

        if segments.isEmpty {
            return [AudioSegment(startTime: 0, endTime: totalDuration)]
        }
        return segments
    }
}
