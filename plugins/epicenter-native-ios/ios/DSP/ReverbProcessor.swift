import Foundation

final class ReverbProcessor {
    private(set) var enabled = false

    func setEnabled(_ enabled: Bool) -> [String: Any] {
        self.enabled = enabled
        return ["status": NativeAudioStubStatus.notImplemented.rawValue, "enabled": enabled]
    }
}
