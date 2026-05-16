import Foundation

final class NativePlaybackController {
    private let engine = NativeAudioEngine()

    func getPlaybackState() -> [String: Any] {
        engine.getPlaybackState()
    }

    func notImplementedResponse(_ method: String) -> [String: Any] {
        ["status": NativeAudioStubStatus.notImplemented.rawValue, "method": method]
    }
}
