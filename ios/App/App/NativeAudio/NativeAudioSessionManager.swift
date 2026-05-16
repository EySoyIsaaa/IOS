import Foundation

final class NativeAudioSessionManager {
    func configureForFuturePlayback() -> [String: Any] {
        ["status": NativeAudioStubStatus.notImplemented.rawValue, "category": "playback"]
    }
}
