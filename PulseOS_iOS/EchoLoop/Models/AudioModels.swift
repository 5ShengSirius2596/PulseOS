import Foundation

/// 复读模式
enum RepeatMode: String, CaseIterable, Codable, Identifiable {
    case smart = "智能断句"
    case subtitle = "字幕断句"
    case abLoop = "AB模式"

    var id: String { rawValue }
}

/// 音频分段（单句）模型
struct AudioSegment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String = ""
    var translation: String = ""
    var isFavorite: Bool = false

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }
}

/// 音频条目元数据
struct AudioTrack: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    /// 保存在 Documents/AudioLibrary/ 下的相对文件名
    var audioFileName: String
    /// 可选配套字幕相对文件名 (.srt / .lrc)
    var subtitleFileName: String?
    var duration: TimeInterval
    var collectionName: String = "默认合集"
    var createdAt: Date = Date()
    var segments: [AudioSegment] = []
    /// 今日学习时长（秒）
    var todayStudySeconds: TimeInterval = 0
    /// 累计学习时长（秒）
    var totalStudySeconds: TimeInterval = 0
    /// 上次记录今日时长的日期字符串 (yyyy-MM-dd)
    var lastStudyDayKey: String = AudioTrack.currentDayKey()
    /// 上次播放停留的段落索引
    var lastSegmentIndex: Int = 0

    static func currentDayKey(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    mutating func refreshTodayIfNeeded() {
        let key = Self.currentDayKey()
        if lastStudyDayKey != key {
            todayStudySeconds = 0
            lastStudyDayKey = key
        }
    }
}

/// 字幕条目
struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let primaryText: String
    let secondaryText: String
}

/// 时间格式化辅助
enum TimeFormatters {
    /// 格式化为 MM:SS.d（如 00:31.8）
    static func mmssTenth(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalTenths = Int((clamped * 10).rounded())
        let tenths = totalTenths % 10
        let totalSeconds = totalTenths / 10
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    /// 格式化为 MM:SS（如 00:31）
    static func mmss(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalSeconds = Int(clamped.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 格式化为 HH:MM:SS（如 00:10:45）
    static func hhmmss(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalSeconds = Int(clamped.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
