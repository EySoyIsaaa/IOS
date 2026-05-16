import Foundation

enum NativeAudioStubStatus: String {
    case notImplemented = "not_implemented"
}

struct NativePlaybackStateStub {
    let isPlaying: Bool = false
    let currentTime: Double = 0
    let duration: Double = 0
    let currentTrackId: String? = nil

    var dictionary: [String: Any] {
        [
            "status": NativeAudioStubStatus.notImplemented.rawValue,
            "isPlaying": isPlaying,
            "currentTime": currentTime,
            "duration": duration,
            "currentTrackId": currentTrackId as Any,
        ]
    }
}
