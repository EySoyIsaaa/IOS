import Foundation

final class NativeTrackImporter {
    func importTracks() -> [String: Any] {
        [
            "status": NativeAudioStubStatus.notImplemented.rawValue,
            "tracks": [],
        ]
    }
}
