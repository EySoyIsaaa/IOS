import Foundation
import MediaPlayer

final class RemoteCommandManager {
    static let shared = RemoteCommandManager()

    struct Handlers {
        var play: () -> Bool
        var pause: () -> Bool
        var togglePlayPause: () -> Bool
        var next: () -> Bool
        var previous: () -> Bool
        var seek: (Double) -> Bool
    }

    private let commandCenter = MPRemoteCommandCenter.shared()
    private var handlers: Handlers?
    private var isConfigured = false

    private init() {}

    func configure(handlers: Handlers) -> [String: Any] {
        self.handlers = handlers
        guard !isConfigured else {
            return ["status": "ok", "alreadyConfigured": true]
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlers?.play() == true ? .success : .commandFailed
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlers?.pause() == true ? .success : .commandFailed
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handlers?.togglePlayPause() == true ? .success : .commandFailed
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handlers?.next() == true ? .success : .noSuchContent
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlers?.previous() == true ? .success : .noSuchContent
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return self?.handlers?.seek(positionEvent.positionTime) == true ? .success : .commandFailed
        }

        isConfigured = true
        return ["status": "ok", "alreadyConfigured": false]
    }
}
