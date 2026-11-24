import Foundation
import Observation

/// 全局用户设置（使用 UserDefaults 持久化，并在 PrivacyInfo.xcprivacy 声明 CA92.1）
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let defaultRepeatCount = "echoloop.defaultRepeatCount"
        static let fineTuneStep = "echoloop.fineTuneStep"
        static let silenceThresholdDB = "echoloop.silenceThresholdDB"
        static let minSilenceDuration = "echoloop.minSilenceDuration"
        static let minSegmentDuration = "echoloop.minSegmentDuration"
        static let autoAdvanceAfterRepeat = "echoloop.autoAdvanceAfterRepeat"
        static let pauseBetweenRepeats = "echoloop.pauseBetweenRepeats"
        static let showSubtitles = "echoloop.showSubtitles"
        static let showTranslation = "echoloop.showTranslation"
    }

    /// 单句默认循环次数（0 表示无限循环）
    var defaultRepeatCount: Int {
        didSet { UserDefaults.standard.set(defaultRepeatCount, forKey: Keys.defaultRepeatCount) }
    }

    /// AB 左右微调步长（秒）
    var fineTuneStep: Double {
        didSet { UserDefaults.standard.set(fineTuneStep, forKey: Keys.fineTuneStep) }
    }

    /// 智能断句静音阈值（dB，越接近 0 越灵敏，典型值 -34 dB）
    var silenceThresholdDB: Double {
        didSet { UserDefaults.standard.set(silenceThresholdDB, forKey: Keys.silenceThresholdDB) }
    }

    /// 智能断句最短停顿时长（秒，典型值 0.35s）
    var minSilenceDuration: Double {
        didSet { UserDefaults.standard.set(minSilenceDuration, forKey: Keys.minSilenceDuration) }
    }

    /// 智能断句最短成句时长（秒，防止切出过碎短音，典型值 1.2s）
    var minSegmentDuration: Double {
        didSet { UserDefaults.standard.set(minSegmentDuration, forKey: Keys.minSegmentDuration) }
    }

    /// 达到设定循环次数后自动进入下一句
    var autoAdvanceAfterRepeat: Bool {
        didSet { UserDefaults.standard.set(autoAdvanceAfterRepeat, forKey: Keys.autoAdvanceAfterRepeat) }
    }

    /// 每次复读之间停顿时长（秒，方便跟读）
    var pauseBetweenRepeats: Double {
        didSet { UserDefaults.standard.set(pauseBetweenRepeats, forKey: Keys.pauseBetweenRepeats) }
    }

    /// 是否显示字幕文本
    var showSubtitles: Bool {
        didSet { UserDefaults.standard.set(showSubtitles, forKey: Keys.showSubtitles) }
    }

    /// 是否显示中文翻译行
    var showTranslation: Bool {
        didSet { UserDefaults.standard.set(showTranslation, forKey: Keys.showTranslation) }
    }

    init() {
        let ud = UserDefaults.standard
        self.defaultRepeatCount = ud.object(forKey: Keys.defaultRepeatCount) as? Int ?? 5
        self.fineTuneStep = ud.object(forKey: Keys.fineTuneStep) as? Double ?? 0.1
        self.silenceThresholdDB = ud.object(forKey: Keys.silenceThresholdDB) as? Double ?? -34.0
        self.minSilenceDuration = ud.object(forKey: Keys.minSilenceDuration) as? Double ?? 0.35
        self.minSegmentDuration = ud.object(forKey: Keys.minSegmentDuration) as? Double ?? 1.2
        self.autoAdvanceAfterRepeat = ud.object(forKey: Keys.autoAdvanceAfterRepeat) as? Bool ?? true
        self.pauseBetweenRepeats = ud.object(forKey: Keys.pauseBetweenRepeats) as? Double ?? 0.25
        self.showSubtitles = ud.object(forKey: Keys.showSubtitles) as? Bool ?? true
        self.showTranslation = ud.object(forKey: Keys.showTranslation) as? Bool ?? true
    }

    static let repeatCountOptions: [Int] = [1, 2, 3, 5, 8, 10, 20, 0]
    static let fineTuneOptions: [Double] = [0.05, 0.1, 0.2, 0.5]
    static let speedOptions: [Float] = [0.5, 0.65, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]
}
