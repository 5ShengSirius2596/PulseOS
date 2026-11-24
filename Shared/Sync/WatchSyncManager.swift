import Foundation
import WatchConnectivity
import WidgetKit

/// Syncs selected Watch complication skin and custom 5-state PNG images between iPhone and Apple Watch.
public final class WatchSyncManager: NSObject, ObservableObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchSyncManager()

    @Published public var selectedSkin: WatchSkinStyle = SharedStore.shared.loadSkinStyle()
    @Published public var isReachable = false

    private override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public func selectSkin(_ style: WatchSkinStyle) {
        selectedSkin = style
        SharedStore.shared.saveSkinStyle(style)
        WidgetCenter.shared.reloadAllTimelines()

        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["skinStyle": style.rawValue])
    }

    /// Sends a compressed PNG (<= 140x140) for one of the 5 HRV states to Apple Watch.
    public func pushCustomImage(_ pngData: Data, for level: BodyStateLevel) {
        SharedStore.shared.saveCustomImageData(pngData, for: level)
        WidgetCenter.shared.reloadAllTimelines()

        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let url = SharedStore.shared.customImageURL(for: level)
        WCSession.default.transferFile(url, metadata: ["stateLevel": level.rawValue])
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let raw = applicationContext["skinStyle"] as? String,
           let style = WatchSkinStyle(rawValue: raw) {
            SharedStore.shared.saveSkinStyle(style)
            DispatchQueue.main.async {
                self.selectedSkin = style
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let rawLevel = file.metadata?["stateLevel"] as? Int,
              let level = BodyStateLevel(rawValue: rawLevel),
              let data = try? Data(contentsOf: file.fileURL) else { return }
        SharedStore.shared.saveCustomImageData(data, for: level)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
