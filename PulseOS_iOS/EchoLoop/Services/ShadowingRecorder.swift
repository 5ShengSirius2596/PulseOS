import AVFoundation
import Foundation
import Observation

/// 跟读录音与波形对比管理器
@MainActor
@Observable
final class ShadowingRecorder: NSObject {
    var isRecording: Bool = false
    var isPlayingRecording: Bool = false
    var recordingDuration: TimeInterval = 0
    var liveLevel: Float = 0
    var recordedWaveform: [Float] = []
    var hasRecording: Bool = false
    var permissionDenied: Bool = false
    var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var playbackPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("echoloop_shadowing.m4a")
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func startRecording() async {
        stopPlayback()
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            errorMessage = "请在系统设置中开启麦克风权限，以使用录音跟读功能。"
            return
        }
        permissionDenied = false
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "无法启动音频会话：\(error.localizedDescription)"
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let rec = try AVAudioRecorder(url: recordingURL, settings: settings)
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            isRecording = true
            recordingDuration = 0
            recordedWaveform = []
            startMeterTimer()
        } catch {
            errorMessage = "录音启动失败：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        stopMeterTimer()
        hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)

        let url = recordingURL
        Task {
            let wave = await AudioAnalysisService.extractWaveform(url: url, bucketsPerSecond: 25)
            self.recordedWaveform = wave
        }
    }

    func togglePlayRecording() {
        if isPlayingRecording {
            stopPlayback()
        } else {
            playRecording()
        }
    }

    func playRecording() {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: recordingURL)
            player.delegate = self
            player.play()
            playbackPlayer = player
            isPlayingRecording = true
        } catch {
            errorMessage = "回放录音失败：\(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        playbackPlayer?.stop()
        playbackPlayer = nil
        isPlayingRecording = false
    }

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder, self.isRecording else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                let normalized = max(0.05, min(1.0, (power + 50) / 50))
                self.liveLevel = normalized
                self.recordingDuration = rec.currentTime
                self.recordedWaveform.append(normalized)
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        liveLevel = 0
    }
}

extension ShadowingRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingRecording = false
        }
    }
}
