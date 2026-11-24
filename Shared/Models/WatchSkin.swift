import Foundation

/// Visual skin styles for Apple Watch HRV State Complications.
public enum WatchSkinStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case mascot    = "mascot"
    case botanical = "botanical"
    case pixel     = "pixel"
    case orb       = "orb"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mascot:    return "萌宠情绪"
        case .botanical: return "植物生长"
        case .pixel:     return "复古像素"
        case .orb:       return "液态光球"
        }
    }

    public var subtitle: String {
        switch self {
        case .mascot:    return "5 档微表情"
        case .botanical: return "叶片舒展度"
        case .pixel:     return "8-bit 血条"
        case .orb:       return "玻璃能量场"
        }
    }
}
