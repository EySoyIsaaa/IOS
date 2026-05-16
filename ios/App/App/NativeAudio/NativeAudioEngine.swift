import Foundation

final class NativeAudioEngine {
    func getPlaybackState() -> [String: Any] {
        NativePlaybackStateStub().dictionary
    }
}
