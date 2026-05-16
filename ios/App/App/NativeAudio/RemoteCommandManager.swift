import Foundation

final class RemoteCommandManager {
    func configure() -> [String: Any] {
        ["status": NativeAudioStubStatus.notImplemented.rawValue]
    }
}
