import Foundation

final class NativePlaybackController {
    private let engine = NativeAudioEngine()
    private let sessionManager = NativeAudioSessionManager()
    private let queueManager = NativeQueueManager()
    private let nowPlayingManager = NowPlayingManager()
    private let remoteCommandManager = RemoteCommandManager.shared
    private let repository: NativeTrackRepository
    private let queue = DispatchQueue(label: "com.epicenter.hifi.native-playback-controller")
    private var progressTimer: Timer?
    private var wasPlayingBeforeInterruption = false
    private var temporarilyFailedTrackIds = Set<String>()
    private var nativeRequestCounter = 0

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
            self?.handleInterruptionEnded()
        }
        sessionManager.onRouteChanged = { [weak self] reason in
            self?.handleRouteChanged(reason: reason)
        }
        configureRemoteCommands()
    }

    func setEventEmitter(_ emitter: @escaping (String, [String: Any]) -> Void) {
        eventEmitter = emitter
    }

    func setQueue(trackIds: [String], startIndex: Int) -> [String: Any] {
        queue.sync {
            print("[NativeQueue] setQueue count=\(trackIds.count) startIndex=\(startIndex)")
            queueManager.setQueue(trackIds: trackIds, startIndex: startIndex)
            print("[NativeQueue] currentIndex=\(self.queueManager.currentIndex) currentTrackId=\(self.queueManager.currentTrackId ?? "nil")")
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
            updateNowPlayingPlayback(from: state, playbackRate: 0, force: true)
            emit("playbackStateChanged", state)
            return state
        }
    }

    func seek(seconds: Double) -> [String: Any] {
        queue.sync {
            do {
                try engine.seek(to: seconds)
                let state = engine.playbackState(queue: queueManager.dictionary)
                updateNowPlayingPlayback(from: state, playbackRate: engine.isCurrentlyPlaying ? 1 : 0, force: true)
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
            sessionManager.deactivateIfPossible(keepActiveForQueue: queueManager.currentTrackId != nil)
            stopProgressTimer()
            let state = engine.playbackState(queue: queueManager.dictionary)
            nowPlayingManager.updateStopped(elapsedTime: state["currentTime"] as? Double ?? 0)
            emit("playbackStateChanged", state)
            return state
        }
    }

    func next(source: String = "bridge") -> [String: Any] {
        queue.sync {
            let requestId = nextRequestId()
            print("[NativeQueue] next requested source=\(source) requestId=\(requestId)")
            guard !queueManager.trackIds.isEmpty else {
                print("[NativeQueue] abort queue empty")
                return playbackErrorResponse(code: "empty_queue", message: "No track is queued")
            }
            guard queueManager.currentIndex >= 0, queueManager.currentIndex < queueManager.trackIds.count else {
                print("[NativeQueue] abort index out of range currentIndex=\(queueManager.currentIndex) count=\(queueManager.trackIds.count)")
                return playbackErrorResponse(code: "queue_index_out_of_range", message: "Queue index is out of range")
            }
            guard let nextTrackId = queueManager.moveNext() else {
                print("[NativeQueue] abort index out of range nextIndex=\(queueManager.currentIndex + 1) count=\(queueManager.trackIds.count)")
                return playbackErrorResponse(code: "queue_end", message: "No next track is available")
            }
            print("[NativeQueue] currentIndex=\(self.queueManager.currentIndex) currentTrackId=\(nextTrackId)")
            return playCurrentTrack(requestedTrackId: nextTrackId, shouldRestartLoadedTrack: true)
        }
    }

    func previous(source: String = "bridge") -> [String: Any] {
        queue.sync {
            let requestId = nextRequestId()
            print("[NativeQueue] previous requested source=\(source) requestId=\(requestId)")
            guard !queueManager.trackIds.isEmpty else {
                print("[NativeQueue] abort queue empty")
                return playbackErrorResponse(code: "empty_queue", message: "No track is queued")
            }
            guard queueManager.currentIndex >= 0, queueManager.currentIndex < queueManager.trackIds.count else {
                print("[NativeQueue] abort index out of range currentIndex=\(queueManager.currentIndex) count=\(queueManager.trackIds.count)")
                return playbackErrorResponse(code: "queue_index_out_of_range", message: "Queue index is out of range")
            }
            guard let previousTrackId = queueManager.movePrevious() else {
                print("[NativeQueue] abort index out of range previousIndex=\(queueManager.currentIndex - 1) count=\(queueManager.trackIds.count)")
                do {
                    try engine.seek(to: 0)
                    let state = engine.playbackState(queue: queueManager.dictionary)
                    updateNowPlayingPlayback(from: state, playbackRate: engine.isCurrentlyPlaying ? 1 : 0, force: true)
                    emit("progressChanged", state)
                    return state
                } catch {
                    return playbackErrorResponse(code: "queue_start", message: "No previous track is available")
                }
            }
            print("[NativeQueue] currentIndex=\(self.queueManager.currentIndex) currentTrackId=\(previousTrackId)")
            return playCurrentTrack(requestedTrackId: previousTrackId, shouldRestartLoadedTrack: true)
        }
    }

    func getPlaybackState() -> [String: Any] {
        queue.sync {
            engine.playbackState(queue: queueManager.dictionary)
        }
    }

    func setEpicenterEnabled(_ enabled: Bool) -> [String: Any] {
        queue.sync {
            let response = engine.setEpicenterEnabled(enabled)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setEpicenterParams(intensity: Double?, sweepFreq: Double?, width: Double?, balance: Double?, volume: Double?) -> [String: Any] {
        queue.sync {
            let response = engine.setEpicenterParams(
                intensity: intensity,
                sweepFreq: sweepFreq,
                width: width,
                balance: balance,
                volume: volume
            )
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }


    func setEqEnabled(_ enabled: Bool) -> [String: Any] {
        queue.sync {
            let response = engine.setEqEnabled(enabled)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setEqBand(index: Int, gain: Double) -> [String: Any] {
        queue.sync {
            let response = engine.setEqBand(index: index, gain: gain)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setEqBands(_ gains: [Double]) -> [String: Any] {
        queue.sync {
            let response = engine.setEqBands(gains)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setEqPreset(name: String?, gains: [Double]) -> [String: Any] {
        queue.sync {
            let response = engine.setEqPreset(name: name, gains: gains)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func resetEq() -> [String: Any] {
        queue.sync {
            let response = engine.resetEq()
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setReverbEnabled(_ enabled: Bool) -> [String: Any] {
        queue.sync {
            let response = engine.setReverbEnabled(enabled)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setReverbAmount(_ amount: Double) -> [String: Any] {
        queue.sync {
            let response = engine.setReverbAmount(amount)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setConcertHallEnabled(_ enabled: Bool) -> [String: Any] {
        queue.sync {
            let response = engine.setConcertHallEnabled(enabled)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func setConcertHallAmount(_ amount: Double) -> [String: Any] {
        queue.sync {
            let response = engine.setConcertHallAmount(amount)
            emit("playbackStateChanged", engine.playbackState(queue: queueManager.dictionary))
            return response
        }
    }

    func notImplementedResponse(_ method: String) -> [String: Any] {
        ["status": NativeAudioStubStatus.notImplemented.rawValue, "method": method]
    }

    private func playCurrentTrack(requestedTrackId: String, shouldRestartLoadedTrack: Bool, skipOnFailure: Bool = true) -> [String: Any] {
        guard let track = repository.findTrack(id: requestedTrackId) else {
            return playbackErrorResponse(code: "track_not_found", message: "Track was not found", trackId: requestedTrackId)
        }
        print("[NativePlaybackController] load track playbackUrl=\(track.playbackUrl ?? "nil") originalUrl=\(track.originalUrl ?? track.sourceUri)")
        guard track.optimizationStatus == "ready", let playbackUrl = track.playbackUrl, !playbackUrl.isEmpty else {
            return handlePlaybackFailure(
                code: "playback_url_unavailable",
                message: track.optimizationError ?? "Track playbackUrl is not ready",
                trackId: requestedTrackId,
                skipOnFailure: skipOnFailure
            )
        }

        do {
            try sessionManager.activate()
            let shouldLoadTrack = shouldRestartLoadedTrack || engine.currentTrackId != track.id
            if shouldLoadTrack {
                try engine.load(track: track)
                let loadedState = engine.playbackState(queue: queueManager.dictionary)
                updateNowPlayingMetadata(for: track, from: loadedState, playbackRate: 0)
                print("[NativePlaybackController] currentTrackChanged trackId=\(track.id)")
                emit("currentTrackChanged", ["status": "ok", "track": track.dictionary])
            }
            try engine.play()
            temporarilyFailedTrackIds.remove(track.id)
            let state = engine.playbackState(queue: queueManager.dictionary)
            updateNowPlayingPlayback(from: state, playbackRate: 1, force: true)
            emit("playbackStateChanged", state)
            startProgressTimerIfNeeded()
            return state
        } catch let error as NativeAudioEngine.EngineError {
            stopProgressTimer()
            return handlePlaybackFailure(
                code: error.errorCode,
                message: error.localizedDescription,
                trackId: requestedTrackId,
                skipOnFailure: skipOnFailure
            )
        } catch {
            stopProgressTimer()
            return handlePlaybackFailure(
                code: "play_failed",
                message: error.localizedDescription,
                trackId: requestedTrackId,
                skipOnFailure: skipOnFailure
            )
        }
    }

    private func handlePlaybackFailure(code: String, message: String, trackId: String, skipOnFailure: Bool) -> [String: Any] {
        temporarilyFailedTrackIds.insert(trackId)
        let errorResponse = playbackErrorResponse(code: code, message: message, trackId: trackId)
        guard skipOnFailure, let nextTrackId = moveToNextPlayableTrack(after: trackId) else {
            return errorResponse
        }
        print("[NativePlaybackController] skipping failed track id=\(trackId) next=\(nextTrackId) code=\(code)")
        let state = playCurrentTrack(requestedTrackId: nextTrackId, shouldRestartLoadedTrack: true, skipOnFailure: false)
        if isSuccessfulPlaybackResponse(state) {
            var skipped = state
            skipped["skippedFailedTrackId"] = trackId
            return skipped
        }
        return errorResponse
    }

    private func moveToNextPlayableTrack(after failedTrackId: String) -> String? {
        let snapshot = queueManager.trackIds
        guard snapshot.count > 1 else { return nil }
        let startIndex = max(queueManager.currentIndex, 0)
        for offset in 1..<snapshot.count {
            let candidateIndex = (startIndex + offset) % snapshot.count
            let candidateId = snapshot[candidateIndex]
            if candidateId == failedTrackId || temporarilyFailedTrackIds.contains(candidateId) {
                print("[NativeQueue] skipping failed track id=\(candidateId)")
                continue
            }
            queueManager.setCurrentIndex(candidateIndex)
            return candidateId
        }
        temporarilyFailedTrackIds.removeAll()
        return nil
    }

    private func handleTrackFinished(_ track: NativeTrack) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit("progressChanged", self.engine.playbackState(queue: self.queueManager.dictionary))
            if let nextTrackId = self.queueManager.moveNext() {
                print("[NativeQueue] next requested source=auto-next requestId=auto")
                _ = self.playCurrentTrack(requestedTrackId: nextTrackId, shouldRestartLoadedTrack: true)
            } else {
                self.stopProgressTimer()
                let state = self.engine.playbackState(queue: self.queueManager.dictionary)
                self.nowPlayingManager.updateStopped(elapsedTime: state["currentTime"] as? Double ?? 0)
                self.emit("playbackStateChanged", state)
                self.emit("trackEnded", ["status": "ok", "track": track.dictionary])
            }
        }
    }

    private func handleInterruptionBegan() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.wasPlayingBeforeInterruption = self.engine.isCurrentlyPlaying
            self.engine.pause()
            self.stopProgressTimer()
            let state = self.engine.playbackState(queue: self.queueManager.dictionary)
            self.updateNowPlayingPlayback(from: state, playbackRate: 0, force: true)
            self.emit("playbackStateChanged", state)
        }
    }

    private func handleInterruptionEnded() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let shouldRemainPaused = self.wasPlayingBeforeInterruption
            self.wasPlayingBeforeInterruption = false
            let state = self.engine.playbackState(queue: self.queueManager.dictionary)
            if shouldRemainPaused {
                self.updateNowPlayingPlayback(from: state, playbackRate: 0, force: true)
            }
            self.emit("playbackStateChanged", state)
        }
    }

    private func handleRouteChanged(reason: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if reason == "oldDeviceUnavailable", self.engine.isCurrentlyPlaying {
                self.engine.pause()
                self.stopProgressTimer()
                let state = self.engine.playbackState(queue: self.queueManager.dictionary)
                self.updateNowPlayingPlayback(from: state, playbackRate: 0, force: true)
                self.emit("audioRouteChanged", ["reason": reason])
                self.emit("playbackStateChanged", state)
                return
            }
            self.emit("audioRouteChanged", ["reason": reason])
            self.emit("playbackStateChanged", self.engine.playbackState(queue: self.queueManager.dictionary))
        }
    }

    private func emitPlaybackEvent(_ eventName: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit(eventName, self.engine.playbackState(queue: self.queueManager.dictionary))
        }
    }


    private func configureRemoteCommands() {
        _ = remoteCommandManager.configure(
            handlers: RemoteCommandManager.Handlers(
                play: { [weak self] in self?.isSuccessfulPlaybackResponse(self?.play()) == true },
                pause: { [weak self] in self?.isSuccessfulPlaybackResponse(self?.pause()) == true },
                togglePlayPause: { [weak self] in
                    guard let self = self else { return false }
                    return self.engine.isCurrentlyPlaying
                        ? self.isSuccessfulPlaybackResponse(self.pause())
                        : self.isSuccessfulPlaybackResponse(self.play())
                },
                next: { [weak self] in self?.isSuccessfulPlaybackResponse(self?.next(source: "remote")) == true },
                previous: { [weak self] in self?.isSuccessfulPlaybackResponse(self?.previous(source: "remote")) == true },
                seek: { [weak self] seconds in self?.isSuccessfulPlaybackResponse(self?.seek(seconds: seconds)) == true }
            )
        )
    }

    private func nextRequestId() -> Int {
        nativeRequestCounter += 1
        return nativeRequestCounter
    }

    private func updateNowPlayingMetadata(for track: NativeTrack, from state: [String: Any], playbackRate: Double) {
        nowPlayingManager.updateMetadata(
            for: track,
            duration: state["duration"] as? Double ?? Double(track.durationMs) / 1000.0,
            elapsedTime: state["currentTime"] as? Double ?? 0,
            playbackRate: playbackRate
        )
    }

    private func updateNowPlayingPlayback(from state: [String: Any], playbackRate: Double, force: Bool) {
        nowPlayingManager.updatePlayback(
            elapsedTime: state["currentTime"] as? Double ?? 0,
            playbackRate: playbackRate,
            force: force
        )
    }

    private func isSuccessfulPlaybackResponse(_ response: [String: Any]?) -> Bool {
        response?["status"] as? String == "ok"
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
