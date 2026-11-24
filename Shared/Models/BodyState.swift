import SwiftUI

/// Five physiological states derived from personal 30-day ln(SDNN) HRV baseline.
public enum BodyStateLevel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case highStress = 0
    case mildStress = 1
    case balanced = 2
    case relaxed = 3
    case peak = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .highStress: return "高压预警"
        case .mildStress: return "轻度压力"
        case .balanced:   return "状态平稳"
        case .relaxed:    return "放松恢复"
        case .peak:       return "元气充沛"
        }
    }

    public var shortTitle: String {
        switch self {
        case .highStress: return "高压"
        case .mildStress: return "轻压"
        case .balanced:   return "平稳"
        case .relaxed:    return "放松"
        case .peak:       return "元气"
        }
    }

    public var advice: String {
        switch self {
        case .highStress:
            return "显著低于个人 30 日基线，建议暂停高强度任务，做 1 分钟深呼吸放松。"
        case .mildStress:
            return "交感神经略偏活跃，午后减少咖啡因摄入，注意间隔起身活动。"
        case .balanced:
            return "处于个人正常波动带内，保持当前工作与日常步行节奏即可。"
        case .relaxed:
            return "副交感神经恢复良好，适合深度专注或安排一次中等强度有氧。"
        case .peak:
            return "身体恢复达到近期峰值，今天非常适合冲击训练目标或高挑战工作。"
        }
    }

    public var color: Color {
        switch self {
        case .highStress: return Color(red: 0.94, green: 0.27, blue: 0.27) // Coral Red
        case .mildStress: return Color(red: 0.96, green: 0.62, blue: 0.04) // Amber
        case .balanced:   return Color(red: 0.23, green: 0.51, blue: 0.96) // Clear Blue
        case .relaxed:    return Color(red: 0.08, green: 0.72, blue: 0.65) // Teal
        case .peak:       return Color(red: 0.06, green: 0.73, blue: 0.51) // Emerald
        }
    }

    public var sfSymbol: String {
        switch self {
        case .highStress: return "flame.fill"
        case .mildStress: return "bolt.fill"
        case .balanced:   return "waveform.path.ecg"
        case .relaxed:    return "leaf.fill"
        case .peak:       return "sparkles"
        }
    }
}
