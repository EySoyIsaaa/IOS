import AVFoundation
import Foundation

final class NativeAudioSessionManager: NSObject {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: (() -> Void)?
    var onRouteChanged: ((String) -> Void)?

    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [])
    }

    func activate() throws {
        try configureForPlayback()
        try session.setActive(true)
    }

    func deactivateIfPossible() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func configureForFuturePlayback() -> [String: Any] {
        do {
            try configureForPlayback()
            return ["status": "ok", "category": "playback"]
        } catch {
            return ["status": "error", "message": error.localizedDescription]
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            onInterruptionEnded?()
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        let reason: String
        if let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
           let routeReason = AVAudioSession.RouteChangeReason(rawValue: rawReason) {
            reason = routeReason.description
        } else {
            reason = "unknown"
        }
        onRouteChanged?(reason)
    }
}

private extension AVAudioSession.RouteChangeReason {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "unknown"
        }
    }
}
