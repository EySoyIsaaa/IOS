import Foundation
import MediaPlayer

final class RemoteCommandManager {
    static let shared = RemoteCommandManager()

    struct Handlers {
        var play: () -> Bool
        var pause: () -> Bool
        var togglePlayPause: () -> Bool
        var next: (String) -> Bool
        var previous: (String) -> Bool
        var seek: (Double) -> Bool
    }

    private let commandCenter = MPRemoteCommandCenter.shared()
    private var handlers: Handlers?
    private var isRegistered = false
    private var remoteRequestCounter = 0

    private init() {}

    func configure(handlers: Handlers) -> [String: Any] {
        self.handlers = handlers
        guard !isRegistered else {
            print("[RemoteCommandManager] already registered, skipping")
            return ["status": "ok", "alreadyConfigured": true]
        }
        print("[RemoteCommandManager] registering remote commands")
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        print("[RemoteCommandManager] registering remote commands")
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        print("[RemoteCommandManager] registering remote commands")
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        print("[RemoteCommandManager] registering remote commands")
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false

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
            guard let self = self else { return .commandFailed }
            let requestId = self.nextRemoteRequestId(prefix: "remote-next")
            print("[RemoteCommand] next requestId=\(requestId)")
            return self.handlers?.next(requestId) == true ? .success : .noSuchContent
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            let requestId = self.nextRemoteRequestId(prefix: "remote-previous")
            print("[RemoteCommand] previous requestId=\(requestId)")
            return self.handlers?.previous(requestId) == true ? .success : .noSuchContent
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return self?.handlers?.seek(positionEvent.positionTime) == true ? .success : .commandFailed
        }

        isRegistered = true
        return ["status": "ok", "alreadyConfigured": false]
    }

    private func nextRemoteRequestId(prefix: String) -> String {
        remoteRequestCounter += 1
        return "\(prefix)-\(remoteRequestCounter)"
    }
}
