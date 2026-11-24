import Foundation

/// App Group shared persistence for iOS App, watchOS App, and Watch WidgetKit Extension.
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    /// Must match the App Group ID configured in project.yml and all 3 *.entitlements files.
    public static let appGroupID = "group.com.personal.pulseos"

    private let snapshotKey = "pulseos.health.snapshot.v1"
    private let skinStyleKey = "pulseos.watch.skin.style.v1"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    private var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    // MARK: - Snapshot

    public func saveSnapshot(_ snapshot: HealthSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    public func loadSnapshot() -> HealthSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode(HealthSnapshot.self, from: data) else {
            return .sample
        }
        return decoded
    }

    // MARK: - Selected Skin

    public func saveSkinStyle(_ style: WatchSkinStyle) {
        defaults.set(style.rawValue, forKey: skinStyleKey)
    }

    public func loadSkinStyle() -> WatchSkinStyle {
        guard let raw = defaults.string(forKey: skinStyleKey),
              let style = WatchSkinStyle(rawValue: raw) else {
            return .mascot
        }
        return style
    }

    // MARK: - Custom 5-State Images (PNG bytes stored in App Group container)

    public func customImageURL(for level: BodyStateLevel) -> URL {
        containerURL.appendingPathComponent("custom_skin_state_\(level.rawValue).png")
    }

    public func saveCustomImageData(_ pngData: Data, for level: BodyStateLevel) {
        let url = customImageURL(for: level)
        try? pngData.write(to: url, options: .atomic)
    }

    public func loadCustomImageData(for level: BodyStateLevel) -> Data? {
        try? Data(contentsOf: customImageURL(for: level))
    }

    public func removeCustomImage(for level: BodyStateLevel) {
        try? FileManager.default.removeItem(at: customImageURL(for: level))
    }
}
