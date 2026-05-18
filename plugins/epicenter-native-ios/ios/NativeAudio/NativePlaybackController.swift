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
    private var transitionCounter = 0
    private var isTransitioningTrack = false
    private var activeTransitionRequestId: String?
    private var activeTransitionSource: String?
    private var activeTransitionStartedAt: Date?

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
            temporarilyFailedTrackIds.removeAll()
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
            let requestId = nextRequestId(prefix: "native-play")
            if isTransitioningTrack, !transitionLockExpired() {
                let active = activeTransitionRequestId ?? "nil"
                print("[NativeQueue] ignored play while transitioning requestId=\(requestId) activeRequestId=\(active)")
                return ["status": "ignored", "requestId": requestId, "activeRequestId": active]
            }
            beginTransition(requestId: requestId, source: "play")
            defer { endTransition(requestId: requestId, reason: "play-finished") }

            if let trackId = trackId?.nilIfBlank {
                if let queuedIndex = queueManager.trackIds.firstIndex(of: trackId) {
                    guard let track = validateCandidate(index: queuedIndex, requestId: requestId) else {
                        return playbackErrorResponse(code: "no_playable_tracks", message: "Requested track is not playable", trackId: trackId, requestId: requestId)
                    }
                    return loadTrack(track, at: queuedIndex, requestId: requestId, shouldRestartLoadedTrack: false, skipOnFailure: true)
                }
                guard let track = repository.findTrack(id: trackId) else {
                    print("[NativePlaybackController] reject reason=track_not_found requestId=\(requestId) trackId=\(trackId)")
                    return playbackErrorResponse(code: "track_not_found", message: "Track was not found", trackId: trackId, requestId: requestId)
                }
                guard validateStandaloneTrack(track, requestId: requestId) else {
                    return playbackErrorResponse(code: "no_playable_tracks", message: "Requested track is not playable", trackId: trackId, requestId: requestId)
                }
                return loadTrack(track, at: 0, requestId: requestId, shouldRestartLoadedTrack: false, skipOnFailure: true, replaceQueueOnSuccess: [track.id])
            }

            guard let requestedTrackId = queueManager.currentTrackId,
                  let index = queueManager.trackIds.firstIndex(of: requestedTrackId) else {
                return playbackErrorResponse(code: "empty_queue", message: "No track is queued", requestId: requestId)
            }
            guard let track = validateCandidate(index: index, requestId: requestId) else {
                return playbackErrorResponse(code: "no_playable_tracks", message: "Queued track is not playable", trackId: requestedTrackId, requestId: requestId)
            }
            return loadTrack(track, at: index, requestId: requestId, shouldRestartLoadedTrack: false, skipOnFailure: true)
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

    func next(source: String = "bridge", requestId suppliedRequestId: String? = nil) -> [String: Any] {
        queue.sync {
            let requestId = suppliedRequestId?.nilIfBlank ?? nextRequestId(prefix: "native-next")
            print("[NativeQueue] manual next requested requestId=\(requestId) source=\(source)")
            return performManualTransition(direction: .next, source: source, requestId: requestId)
        }
    }

    func previous(source: String = "bridge", requestId suppliedRequestId: String? = nil) -> [String: Any] {
        queue.sync {
            let requestId = suppliedRequestId?.nilIfBlank ?? nextRequestId(prefix: "native-previous")
            print("[NativeQueue] manual previous requested requestId=\(requestId) source=\(source)")
            return performManualTransition(direction: .previous, source: source, requestId: requestId)
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

    private enum TransitionDirection: String {
        case next
        case previous
    }

    private func playCurrentTrack(requestedTrackId: String, shouldRestartLoadedTrack: Bool, skipOnFailure: Bool = true, requestId: String? = nil) -> [String: Any] {
        guard let track = repository.findTrack(id: requestedTrackId) else {
            print("[NativePlaybackController] reject reason=track_not_found id=\(requestedTrackId)")
            return playbackErrorResponse(code: "track_not_found", message: "Track was not found", trackId: requestedTrackId, requestId: requestId)
        }
        let index = queueManager.trackIds.firstIndex(of: requestedTrackId) ?? queueManager.currentIndex
        let id = requestId ?? nextRequestId(prefix: "native-play")
        return loadTrack(track, at: index, requestId: id, shouldRestartLoadedTrack: shouldRestartLoadedTrack, skipOnFailure: skipOnFailure)
    }

    private func performManualTransition(direction: TransitionDirection, source: String, requestId: String) -> [String: Any] {
        if isTransitioningTrack, !transitionLockExpired() {
            let active = activeTransitionRequestId ?? "nil"
            print("[NativeQueue] ignored \(direction.rawValue) while transitioning requestId=\(requestId) activeRequestId=\(active)")
            return ["status": "ignored", "requestId": requestId, "activeRequestId": active]
        }
        beginTransition(requestId: requestId, source: source)
        defer { endTransition(requestId: requestId, reason: "manual-transition-finished") }

        print("[NativeQueue] \(direction.rawValue) ENTER requestId=\(requestId) source=\(source) transitionCounter=\(transitionCounter) currentIndex=\(queueManager.currentIndex) currentTrackId=\(queueManager.currentTrackId ?? "nil") queueCount=\(queueManager.trackIds.count)")
        guard !queueManager.trackIds.isEmpty else {
            print("[NativeQueue] abort queue empty")
            return playbackErrorResponse(code: "empty_queue", message: "No track is queued", requestId: requestId)
        }
        guard queueManager.currentIndex >= 0, queueManager.currentIndex < queueManager.trackIds.count else {
            print("[NativeQueue] abort index out of range currentIndex=\(queueManager.currentIndex) count=\(queueManager.trackIds.count)")
            return playbackErrorResponse(code: "queue_index_out_of_range", message: "Queue index is out of range", requestId: requestId)
        }

        let indices: [Int]
        switch direction {
        case .next:
            indices = queueManager.currentIndex + 1 < queueManager.trackIds.count ? Array((queueManager.currentIndex + 1)..<queueManager.trackIds.count) : []
        case .previous:
            indices = queueManager.currentIndex > 0 ? Array(stride(from: queueManager.currentIndex - 1, through: 0, by: -1)) : []
        }

        guard !indices.isEmpty else {
            if direction == .previous {
                do {
                    try engine.seek(to: 0)
                    let state = engine.playbackState(queue: queueManager.dictionary)
                    updateNowPlayingPlayback(from: state, playbackRate: engine.isCurrentlyPlaying ? 1 : 0, force: true)
                    emit("progressChanged", state)
                    print("[NativeQueue] previous EXIT requestId=\(requestId)")
                    return state
                } catch {
                    return playbackErrorResponse(code: "queue_start", message: "No previous track is available", requestId: requestId)
                }
            }
            print("[NativeQueue] abort index out of range nextIndex=\(queueManager.currentIndex + 1) count=\(queueManager.trackIds.count)")
            return playbackErrorResponse(code: "queue_end", message: "No next track is available", requestId: requestId)
        }

        for index in indices {
            let candidateId = queueManager.trackIds[index]
            print("[NativeQueue] \(direction.rawValue) candidate requestId=\(requestId) nextIndex=\(index) candidateId=\(candidateId)")
            guard let track = validateCandidate(index: index, requestId: requestId) else { continue }
            let result = loadTrack(track, at: index, requestId: requestId, shouldRestartLoadedTrack: true, skipOnFailure: true)
            print("[NativeQueue] \(direction.rawValue) EXIT requestId=\(requestId)")
            return result
        }

        return playbackErrorResponse(code: "no_playable_tracks", message: "No playable track candidate is available", requestId: requestId)
    }

    private func validateCandidate(index: Int, requestId: String) -> NativeTrack? {
        guard index >= 0, index < queueManager.trackIds.count else {
            print("[NativePlaybackController] reject reason=queue_index_out_of_range requestId=\(requestId) index=\(index)")
            return nil
        }
        let trackId = queueManager.trackIds[index]
        guard !temporarilyFailedTrackIds.contains(trackId) else {
            print("[NativeQueue] skipping failed track id=\(trackId)")
            return nil
        }
        guard let track = repository.findTrack(id: trackId) else {
            print("[NativePlaybackController] reject reason=track_not_found requestId=\(requestId) trackId=\(trackId)")
            temporarilyFailedTrackIds.insert(trackId)
            return nil
        }
        guard track.optimizationStatus == "ready" else {
            print("[NativePlaybackController] reject reason=optimization_not_ready requestId=\(requestId) trackId=\(trackId) status=\(track.optimizationStatus) error=\(track.optimizationError ?? "nil")")
            temporarilyFailedTrackIds.insert(trackId)
            return nil
        }
        guard let playbackUrl = track.playbackUrl, !playbackUrl.isEmpty else {
            print("[NativePlaybackController] reject reason=playback_url_missing requestId=\(requestId) trackId=\(trackId)")
            temporarilyFailedTrackIds.insert(trackId)
            return nil
        }
        let info = playbackFileInfo(path: playbackUrl)
        guard info.exists, info.size > 0 else {
            print("[NativePlaybackController] reject reason=playback_file_missing requestId=\(requestId) trackId=\(trackId) path=\(playbackUrl) exists=\(info.exists) size=\(info.size)")
            temporarilyFailedTrackIds.insert(trackId)
            return nil
        }
        return track
    }

    private func loadTrack(_ track: NativeTrack, at index: Int, requestId: String, shouldRestartLoadedTrack: Bool, skipOnFailure: Bool, replaceQueueOnSuccess: [String]? = nil) -> [String: Any] {
        print("[NativePlaybackController] will load id=\(track.id) title=\(track.title) optimizationStatus=\(track.optimizationStatus) playbackUrl=\(track.playbackUrl ?? "nil") optimizedUrl=\(track.optimizedUrl ?? "nil") originalUrl=\(track.originalUrl ?? track.sourceUri)")
        print("[NativePlaybackController] load requestId=\(requestId) trackId=\(track.id)")
        let info = playbackFileInfo(path: track.playbackUrl)
        print("[NativePlaybackController] playback file exists \(info.exists) size=\(info.size)")

        guard track.optimizationStatus == "ready" else {
            print("[NativePlaybackController] reject reason=optimization_not_ready requestId=\(requestId) trackId=\(track.id)")
            return handlePlaybackFailure(code: "optimization_not_ready", message: track.optimizationError ?? "Track optimization is not ready", trackId: track.id, originalRequestId: requestId, skipOnFailure: skipOnFailure)
        }
        guard let playbackUrl = track.playbackUrl, !playbackUrl.isEmpty else {
            print("[NativePlaybackController] reject reason=playback_url_missing requestId=\(requestId) trackId=\(track.id)")
            return handlePlaybackFailure(code: "playback_url_missing", message: "Track playbackUrl is missing", trackId: track.id, originalRequestId: requestId, skipOnFailure: skipOnFailure)
        }
        guard info.exists, info.size > 0 else {
            print("[NativePlaybackController] reject reason=playback_file_missing requestId=\(requestId) trackId=\(track.id)")
            return handlePlaybackFailure(code: "playback_file_missing", message: "Track playback file is missing", trackId: track.id, originalRequestId: requestId, skipOnFailure: skipOnFailure)
        }

        do {
            try sessionManager.activate()
            let shouldLoadTrack = shouldRestartLoadedTrack || engine.currentTrackId != track.id || replaceQueueOnSuccess != nil
            if shouldLoadTrack {
                try engine.load(track: track)
                if let replacementQueue = replaceQueueOnSuccess {
                    queueManager.setQueue(trackIds: replacementQueue, startIndex: index)
                } else {
                    queueManager.setCurrentIndex(index)
                }
                let loadedState = engine.playbackState(queue: queueManager.dictionary)
                updateNowPlayingMetadata(for: track, from: loadedState, playbackRate: 0)
                print("[NativePlaybackController] currentTrackChanged requestId=\(requestId) trackId=\(track.id) index=\(index)")
                emit("currentTrackChanged", ["status": "ok", "requestId": requestId, "track": track.dictionary])
            }
            temporarilyFailedTrackIds.remove(track.id)
            var state = engine.playbackState(queue: queueManager.dictionary)
            state["requestId"] = requestId
            updateNowPlayingPlayback(from: state, playbackRate: 1, force: true)
            emit("playbackStateChanged", state.merging(["requestId": requestId]) { current, _ in current })
            startProgressTimerIfNeeded()
            return state.merging(["requestId": requestId]) { current, _ in current }
        } catch let error as NativeAudioEngine.EngineError {
            stopProgressTimer()
            print("[NativePlaybackController] reject reason=\(error.errorCode) requestId=\(requestId) trackId=\(track.id) error=\(error.localizedDescription)")
            return handlePlaybackFailure(code: error.errorCode, message: error.localizedDescription, trackId: track.id, originalRequestId: requestId, skipOnFailure: skipOnFailure)
        } catch {
            stopProgressTimer()
            print("[NativePlaybackController] reject reason=decode_failed requestId=\(requestId) trackId=\(track.id) error=\(error.localizedDescription)")
            return handlePlaybackFailure(code: "decode_failed", message: error.localizedDescription, trackId: track.id, originalRequestId: requestId, skipOnFailure: skipOnFailure)
        }
        return errorResponse
    }

    private func handlePlaybackFailure(code: String, message: String, trackId: String, originalRequestId: String, skipOnFailure: Bool) -> [String: Any] {
        temporarilyFailedTrackIds.insert(trackId)
        let errorResponse = playbackErrorResponse(code: code, message: message, trackId: trackId, requestId: originalRequestId)
        guard skipOnFailure else { return errorResponse }
        print("[NativeQueue] failure skip requested originalRequestId=\(originalRequestId) failedTrackId=\(trackId)")
        while let recovery = recoveryCandidate(after: trackId, originalRequestId: originalRequestId) {
            print("[NativeQueue] skip failed track originalRequestId=\(originalRequestId) failedTrackId=\(trackId) nextCandidateId=\(recovery.track.id)")
            let state = loadTrack(recovery.track, at: recovery.index, requestId: originalRequestId, shouldRestartLoadedTrack: true, skipOnFailure: false)
            if isSuccessfulPlaybackResponse(state) {
                print("[NativeQueue] recovery ended requestId=\(originalRequestId)")
                var skipped = state
                skipped["skippedFailedTrackId"] = trackId
                return skipped
            }
        }
        print("[NativeQueue] recovery ended requestId=\(originalRequestId)")
        temporarilyFailedTrackIds.removeAll()
        return errorResponse
    }

    private func recoveryCandidate(after failedTrackId: String, originalRequestId: String) -> (index: Int, track: NativeTrack)? {
        let snapshot = queueManager.trackIds
        guard snapshot.count > 1 else { return nil }
        let startIndex = snapshot.firstIndex(of: failedTrackId) ?? queueManager.currentIndex
        for offset in 1..<snapshot.count {
            let candidateIndex = (startIndex + offset) % snapshot.count
            let candidateId = snapshot[candidateIndex]
            if candidateId == failedTrackId { continue }
            print("[NativeQueue] recovery candidate selected index=\(candidateIndex) trackId=\(candidateId)")
            if let track = validateCandidate(index: candidateIndex, requestId: originalRequestId) {
                return (candidateIndex, track)
            }
        }
        return nil
    }

    private func playbackFileInfo(path: String?) -> (exists: Bool, size: Int64) {
        guard let path = path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return (false, 0)
        }
        let size = ((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return (true, Int64(size))
    }

    private func beginTransition(requestId: String, source: String) {
        transitionCounter += 1
        isTransitioningTrack = true
        activeTransitionRequestId = requestId
        activeTransitionSource = source
        activeTransitionStartedAt = Date()
    }

    private func endTransition(requestId: String, reason: String) {
        guard activeTransitionRequestId == requestId else { return }
        isTransitioningTrack = false
        activeTransitionRequestId = nil
        activeTransitionSource = nil
        activeTransitionStartedAt = nil
        print("[NativeQueue] transition ended requestId=\(requestId) reason=\(reason)")
    }

    private func transitionLockExpired() -> Bool {
        guard let started = activeTransitionStartedAt else { return true }
        if Date().timeIntervalSince(started) > 2.0 {
            print("[NativeQueue] transition timeout activeRequestId=\(activeTransitionRequestId ?? "nil") source=\(activeTransitionSource ?? "nil")")
            isTransitioningTrack = false
            activeTransitionRequestId = nil
            activeTransitionSource = nil
            activeTransitionStartedAt = nil
            return true
        }
        return false
    }

    private func handleTrackFinished(_ track: NativeTrack) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit("progressChanged", self.engine.playbackState(queue: self.queueManager.dictionary))
            let requestId = self.nextRequestId(prefix: "auto-next")
            if self.isTransitioningTrack, !self.transitionLockExpired() {
                print("[NativeTransition] auto-next ignored while busy requestId=\(requestId) activeRequestId=\(self.activeTransitionRequestId ?? "nil")")
                return
            }
            self.beginTransition(requestId: requestId, source: "auto-next")
            defer { self.endTransition(requestId: requestId, reason: "auto-next-finished") }
            if let candidate = self.recoveryCandidate(after: track.id, originalRequestId: requestId) {
                print("[NativeQueue] next requested source=auto-next requestId=\(requestId)")
                _ = self.loadTrack(candidate.track, at: candidate.index, requestId: requestId, shouldRestartLoadedTrack: true, skipOnFailure: true)
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
                next: { [weak self] requestId in self?.isSuccessfulPlaybackResponse(self?.next(source: "remote", requestId: requestId)) == true },
                previous: { [weak self] requestId in self?.isSuccessfulPlaybackResponse(self?.previous(source: "remote", requestId: requestId)) == true },
                seek: { [weak self] seconds in self?.isSuccessfulPlaybackResponse(self?.seek(seconds: seconds)) == true }
            )
        )
    }

    private func nextRequestId(prefix: String = "native") -> String {
        nativeRequestCounter += 1
        return "\(prefix)-\(nativeRequestCounter)"
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

    private func playbackErrorResponse(code: String, message: String, trackId: String? = nil, requestId: String? = nil) -> [String: Any] {
        var response: [String: Any] = [
            "status": "error",
            "code": code,
            "message": message,
        ]
        if let trackId = trackId {
            response["trackId"] = trackId
        }
        if let requestId = requestId {
            response["requestId"] = requestId
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
        if eventName == "currentTrackChanged", let track = data["track"] as? [String: Any] {
            print("[Bridge] event currentTrackChanged requestId=\(data["requestId"] as? String ?? "none") trackId=\(track["id"] as? String ?? "nil")")
        }
        DispatchQueue.main.async {
            eventEmitter(eventName, data)
        }
    }
}


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
