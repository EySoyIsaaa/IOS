import Foundation

final class NativePlaybackController {
    private let engine = NativeAudioEngine()
    private let sessionManager = NativeAudioSessionManager()
    private let queueManager = NativeQueueManager()
    private let repository: NativeTrackRepository
    private let queue = DispatchQueue(label: "com.epicenter.hifi.native-playback-controller")
    private var progressTimer: Timer?

    var eventEmitter: ((String, [String: Any]) -> Void)?

    init(repository: NativeTrackRepository = NativeTrackRepository()) {
        self.repository = repository
        engine.onTrackFinished = { [weak self] track in
            self?.handleTrackFinished(track)
        }
        sessionManager.onInterruptionBegan = { [weak self] in
            self?.handleInterruptionBegan()
        }
        sessionManager.onInterruptionEnded = { [weak self] in
            self?.emitPlaybackEvent("playbackStateChanged")
        }
        sessionManager.onRouteChanged = { [weak self] reason in
            self?.emit("audioRouteChanged", ["reason": reason])
            self?.emitPlaybackEvent("playbackStateChanged")
        }
    }

    func setEventEmitter(_ emitter: @escaping (String, [String: Any]) -> Void) {
        eventEmitter = emitter
    }

    func setQueue(trackIds: [String], startIndex: Int) -> [String: Any] {
        queue.sync {
            queueManager.setQueue(trackIds: trackIds, startIndex: startIndex)
            let response: [String: Any] = [
                "status": "ok",
                "queue": queueManager.dictionary,
            ]
            emit("queueChanged", response)
            return response
        }
    }

    func play(trackId: String? = nil) -> [String: Any] {
        queue.sync {
            if let trackId = trackId, !trackId.isEmpty {
                queueManager.setCurrentTrackId(trackId)
            }
            guard let requestedTrackId = queueManager.currentTrackId else {
                return playbackErrorResponse(code: "empty_queue", message: "No track is queued")
            }
            return playCurrentTrack(requestedTrackId: requestedTrackId, shouldRestartLoadedTrack: false)
        }
    }

    func pause() -> [String: Any] {
        queue.sync {
            engine.pause()
            stopProgressTimer()
            let state = engine.playbackState(queue: queueManager.dictionary)
            emit("playbackStateChanged", state)
            return state
        }
    }

    func seek(seconds: Double) -> [String: Any] {
        queue.sync {
            do {
                try engine.seek(to: seconds)
                let state = engine.playbackState(queue: queueManager.dictionary)
                emit("progressChanged", state)
                emit("playbackStateChanged", state)
                startProgressTimerIfNeeded()
                return state
            } catch {
                return playbackErrorResponse(code: "seek_failed", message: error.localizedDescription)
            }
        }
    }

    func stop() -> [String: Any] {
        queue.sync {
            engine.stop(clearTrack: false)
            sessionManager.deactivateIfPossible()
            stopProgressTimer()
            let state = engine.playbackState(queue: queueManager.dictionary)
            emit("playbackStateChanged", state)
            return state
        }
    }

    func next() -> [String: Any] {
        queue.sync {
            guard let nextTrackId = queueManager.moveNext() else {
                return playbackErrorResponse(code: "queue_end", message: "No next track is available")
            }
            return playCurrentTrack(requestedTrackId: nextTrackId, shouldRestartLoadedTrack: true)
        }
    }

    func previous() -> [String: Any] {
        queue.sync {
            guard let previousTrackId = queueManager.movePrevious() else {
                do {
                    try engine.seek(to: 0)
                    let state = engine.playbackState(queue: queueManager.dictionary)
                    emit("progressChanged", state)
                    return state
                } catch {
                    return playbackErrorResponse(code: "queue_start", message: "No previous track is available")
                }
            }
            return playCurrentTrack(requestedTrackId: previousTrackId, shouldRestartLoadedTrack: true)
        }
    }

    func getPlaybackState() -> [String: Any] {
        queue.sync {
            engine.playbackState(queue: queueManager.dictionary)
        }
    }

    func notImplementedResponse(_ method: String) -> [String: Any] {
        ["status": NativeAudioStubStatus.notImplemented.rawValue, "method": method]
    }

    private func playCurrentTrack(requestedTrackId: String, shouldRestartLoadedTrack: Bool) -> [String: Any] {
        guard let track = repository.findTrack(id: requestedTrackId) else {
            return playbackErrorResponse(code: "track_not_found", message: "Track was not found", trackId: requestedTrackId)
        }

        do {
            try sessionManager.activate()
            let shouldLoadTrack = shouldRestartLoadedTrack || engine.currentTrackId != track.id
            if shouldLoadTrack {
                try engine.load(track: track)
                emit("currentTrackChanged", ["status": "ok", "track": track.dictionary])
            }
            try engine.play()
            let state = engine.playbackState(queue: queueManager.dictionary)
            emit("playbackStateChanged", state)
            startProgressTimerIfNeeded()
            return state
        } catch {
            stopProgressTimer()
            return playbackErrorResponse(code: "play_failed", message: error.localizedDescription, trackId: requestedTrackId)
        }
    }

    private func handleTrackFinished(_ track: NativeTrack) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit("progressChanged", self.engine.playbackState(queue: self.queueManager.dictionary))
            if let nextTrackId = self.queueManager.moveNext() {
                _ = self.playCurrentTrack(requestedTrackId: nextTrackId, shouldRestartLoadedTrack: true)
            } else {
                self.stopProgressTimer()
                let state = self.engine.playbackState(queue: self.queueManager.dictionary)
                self.emit("playbackStateChanged", state)
                self.emit("trackEnded", ["status": "ok", "track": track.dictionary])
            }
        }
    }

    private func handleInterruptionBegan() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.engine.pause()
            self.stopProgressTimer()
            self.emitPlaybackEvent("playbackStateChanged")
        }
    }

    private func emitPlaybackEvent(_ eventName: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit(eventName, self.engine.playbackState(queue: self.queueManager.dictionary))
        }
    }

    private func playbackErrorResponse(code: String, message: String, trackId: String? = nil) -> [String: Any] {
        var response: [String: Any] = [
            "status": "error",
            "code": code,
            "message": message,
        ]
        if let trackId = trackId {
            response["trackId"] = trackId
        }
        emit("playbackError", response)
        return response
    }

    private func startProgressTimerIfNeeded() {
        guard eventEmitter != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.progressTimer == nil else { return }
            self.progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self = self else { return }
                    let state = self.engine.playbackState(queue: self.queueManager.dictionary)
                    self.emit("progressChanged", state)
                    if (state["isPlaying"] as? Bool) != true {
                        self.stopProgressTimer()
                    }
                }
            }
        }
    }

    private func stopProgressTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
    }

    private func emit(_ eventName: String, _ data: [String: Any]) {
        guard let eventEmitter = eventEmitter else { return }
        DispatchQueue.main.async {
            eventEmitter(eventName, data)
        }
    }
}
