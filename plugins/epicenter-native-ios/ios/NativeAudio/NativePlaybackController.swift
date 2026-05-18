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
    private var isTransitioningTrack = false
    private var activeTransitionRequestId: String?
    private var activeTransitionSource: String?
    private var activeTransitionStartedAt: Date?
    private let transitionTimeoutSeconds: TimeInterval = 2.0

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

    func next(source: String = "bridge", requestId incomingRequestId: String? = nil) -> [String: Any] {
        queue.sync {
            let requestId = incomingRequestId?.nilIfBlank ?? nextRequestId(prefix: "native-next")
            print("[NativeQueue] manual next requested requestId=\(requestId) source=\(source)")
            return performManualTransition(direction: "next", step: 1, source: source, requestId: requestId)
        }
    }

    func previous(source: String = "bridge", requestId incomingRequestId: String? = nil) -> [String: Any] {
        queue.sync {
            let requestId = incomingRequestId?.nilIfBlank ?? nextRequestId(prefix: "native-previous")
            print("[NativeQueue] manual previous requested requestId=\(requestId) source=\(source)")
            return performManualTransition(direction: "previous", step: -1, source: source, requestId: requestId)
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

    private func playCurrentTrack(requestedTrackId: String, shouldRestartLoadedTrack: Bool, skipOnFailure: Bool = true, requestId: String? = nil) -> [String: Any] {
        guard let index = queueManager.trackIds.firstIndex(of: requestedTrackId) else {
            return playbackErrorResponse(code: "track_not_found", message: "Track was not found in queue", trackId: requestedTrackId)
        }
        let effectiveRequestId = requestId ?? nextRequestId(prefix: "native-play")
        return loadCandidate(at: index, requestId: effectiveRequestId, source: "play", shouldRestartLoadedTrack: shouldRestartLoadedTrack, allowRecovery: skipOnFailure)
    }

    private func performManualTransition(direction: String, step: Int, source: String, requestId: String) -> [String: Any] {
        clearStaleTransitionIfNeeded()
        if isTransitioningTrack {
            print("[NativeQueue] ignored \(direction) while transitioning requestId=\(requestId) activeRequestId=\(activeTransitionRequestId ?? "nil")")
            var state = engine.playbackState(queue: queueManager.dictionary)
            state["ignored"] = true
            state["requestId"] = requestId
            return state
        }

        isTransitioningTrack = true
        activeTransitionRequestId = requestId
        activeTransitionSource = source
        activeTransitionStartedAt = Date()
        print("[NativeQueue] \(direction) ENTER requestId=\(requestId) source=\(source) transitionCounter=\(nativeRequestCounter) currentIndex=\(queueManager.currentIndex) currentTrackId=\(queueManager.currentTrackId ?? "nil") queueCount=\(queueManager.trackIds.count)")
        defer {
            endTransition(requestId: requestId, direction: direction)
        }

        guard !queueManager.trackIds.isEmpty else {
            print("[NativeQueue] abort queue empty")
            return playbackErrorResponse(code: "empty_queue", message: "No track is queued")
        }
        guard queueManager.currentIndex >= 0, queueManager.currentIndex < queueManager.trackIds.count else {
            print("[NativeQueue] abort index out of range currentIndex=\(queueManager.currentIndex) count=\(queueManager.trackIds.count)")
            return playbackErrorResponse(code: "queue_index_out_of_range", message: "Queue index is out of range")
        }

        let candidateIndex = queueManager.currentIndex + step
        guard candidateIndex >= 0, candidateIndex < queueManager.trackIds.count else {
            print("[NativeQueue] abort index out of range \(direction)Index=\(candidateIndex) count=\(queueManager.trackIds.count)")
            if direction == "previous" {
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
            return playbackErrorResponse(code: "queue_end", message: "No next track is available")
        }
        let candidateId = queueManager.trackIds[candidateIndex]
        print("[NativeQueue] \(direction) candidate requestId=\(requestId) nextIndex=\(candidateIndex) candidateId=\(candidateId)")
        return loadCandidate(at: candidateIndex, requestId: requestId, source: source, shouldRestartLoadedTrack: true, allowRecovery: true)
    }

    private func loadCandidate(at index: Int, requestId: String, source: String, shouldRestartLoadedTrack: Bool, allowRecovery: Bool) -> [String: Any] {
        guard index >= 0, index < queueManager.trackIds.count else {
            print("[NativeQueue] abort index out of range candidateIndex=\(index) count=\(queueManager.trackIds.count)")
            return playbackErrorResponse(code: "queue_index_out_of_range", message: "Queue candidate index is out of range")
        }
        let trackId = queueManager.trackIds[index]
        print("[NativePlaybackController] load requestId=\(requestId) trackId=\(trackId)")
        let validation = validateCandidate(trackId: trackId, index: index)
        guard let track = validation.track else {
            temporarilyFailedTrackIds.insert(trackId)
            print("[NativePlaybackController] reject reason=\(validation.code) requestId=\(requestId) trackId=\(trackId)")
            let response = playbackErrorResponse(code: validation.code, message: validation.message, trackId: trackId)
            if allowRecovery {
                return recoverFromFailedTrack(failedTrackId: trackId, originalRequestId: requestId, errorResponse: response)
            }
            return response
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
                do {
                    try engine.load(track: track)
                } catch let error as NativeAudioEngine.EngineError {
                    stopProgressTimer()
                    temporarilyFailedTrackIds.insert(track.id)
                    print("[NativePlaybackController] reject reason=\(error.errorCode) requestId=\(requestId) trackId=\(track.id)")
                    let response = playbackErrorResponse(code: error.errorCode, message: error.localizedDescription, trackId: track.id)
                    return allowRecovery ? recoverFromFailedTrack(failedTrackId: track.id, originalRequestId: requestId, errorResponse: response) : response
                } catch {
                    stopProgressTimer()
                    temporarilyFailedTrackIds.insert(track.id)
                    print("[NativePlaybackController] reject reason=decode_failed requestId=\(requestId) trackId=\(track.id)")
                    let response = playbackErrorResponse(code: "decode_failed", message: error.localizedDescription, trackId: track.id)
                    return allowRecovery ? recoverFromFailedTrack(failedTrackId: track.id, originalRequestId: requestId, errorResponse: response) : response
                }
                queueManager.setCurrentIndex(index)
                let loadedState = engine.playbackState(queue: queueManager.dictionary)
                updateNowPlayingMetadata(for: track, from: loadedState, playbackRate: 0)
                print("[NativePlaybackController] currentTrackChanged requestId=\(requestId) trackId=\(track.id) index=\(index)")
                emit("currentTrackChanged", ["status": "ok", "requestId": requestId, "track": track.dictionary, "index": index])
            }
            do {
                try engine.play()
            } catch let error as NativeAudioEngine.EngineError {
                stopProgressTimer()
                temporarilyFailedTrackIds.insert(track.id)
                print("[NativePlaybackController] reject reason=\(error.errorCode) requestId=\(requestId) trackId=\(track.id)")
                let response = playbackErrorResponse(code: error.errorCode, message: error.localizedDescription, trackId: track.id)
                return allowRecovery ? recoverFromFailedTrack(failedTrackId: track.id, originalRequestId: requestId, errorResponse: response) : response
            }
            temporarilyFailedTrackIds.remove(track.id)
            var state = engine.playbackState(queue: queueManager.dictionary)
            state["requestId"] = requestId
            updateNowPlayingPlayback(from: state, playbackRate: 1, force: true)
            emit("playbackStateChanged", state)
            startProgressTimerIfNeeded()
            return state
        } catch {
            stopProgressTimer()
            temporarilyFailedTrackIds.insert(track.id)
            print("[NativePlaybackController] reject reason=decode_failed requestId=\(requestId) trackId=\(track.id)")
            let response = playbackErrorResponse(code: "decode_failed", message: error.localizedDescription, trackId: track.id)
            return allowRecovery ? recoverFromFailedTrack(failedTrackId: track.id, originalRequestId: requestId, errorResponse: response) : response
        }
    }

    private func validateCandidate(trackId: String, index: Int) -> (track: NativeTrack?, code: String, message: String) {
        if temporarilyFailedTrackIds.contains(trackId) {
            return (nil, "track_temporarily_failed", "Track previously failed in this queue")
        }
        guard let track = repository.findTrack(id: trackId) else {
            return (nil, "track_not_found", "Track was not found")
        }
        print("[NativePlaybackController] will load id=\(track.id) title=\(track.title) optimizationStatus=\(track.optimizationStatus) playbackUrl=\(track.playbackUrl ?? "nil") optimizedUrl=\(track.optimizedUrl ?? "nil") originalUrl=\(track.originalUrl ?? track.sourceUri)")
        guard track.optimizationStatus == "ready" else {
            return (nil, "optimization_not_ready", track.optimizationError ?? "Track optimization is not ready")
        }
        guard let playbackUrl = track.playbackUrl?.nilIfBlank else {
            return (nil, "playback_url_missing", "Track playbackUrl is missing")
        }
        let fileInfo = playbackFileInfo(path: playbackUrl)
        print("[NativePlaybackController] playback file exists \(fileInfo.exists) size=\(fileInfo.size)")
        guard fileInfo.exists else {
            return (nil, "playback_file_missing", "Playback file is missing")
        }
        guard fileInfo.size > 0 else {
            return (nil, "playback_file_missing", "Playback file is empty")
        }
        return (track, "ok", "ok")
    }

    private func recoverFromFailedTrack(failedTrackId: String, originalRequestId: String, errorResponse: [String: Any]) -> [String: Any] {
        print("[NativeQueue] failure skip requested originalRequestId=\(originalRequestId) failedTrackId=\(failedTrackId)")
        guard let candidateIndex = nextRecoveryCandidateIndex(after: failedTrackId) else {
            temporarilyFailedTrackIds.removeAll()
            print("[NativeQueue] recovery ended requestId=\(originalRequestId)")
            return errorResponse
        }
        let candidateId = queueManager.trackIds[candidateIndex]
        print("[NativeQueue] skip failed track originalRequestId=\(originalRequestId) failedTrackId=\(failedTrackId) nextCandidateId=\(candidateId)")
        print("[NativeQueue] recovery candidate selected index=\(candidateIndex) trackId=\(candidateId)")
        var state = loadCandidate(at: candidateIndex, requestId: originalRequestId, source: "recovery", shouldRestartLoadedTrack: true, allowRecovery: true)
        print("[NativeQueue] recovery ended requestId=\(originalRequestId)")
        if isSuccessfulPlaybackResponse(state) {
            state["skippedFailedTrackId"] = failedTrackId
            return state
        }
        return errorResponse
    }

    private func nextRecoveryCandidateIndex(after failedTrackId: String) -> Int? {
        let snapshot = queueManager.trackIds
        guard snapshot.count > 1 else { return nil }
        let startIndex = snapshot.firstIndex(of: failedTrackId) ?? max(queueManager.currentIndex, 0)
        for offset in 1..<snapshot.count {
            let candidateIndex = (startIndex + offset) % snapshot.count
            let candidateId = snapshot[candidateIndex]
            if candidateId == failedTrackId || temporarilyFailedTrackIds.contains(candidateId) {
                print("[NativeQueue] skipping failed track id=\(candidateId)")
                continue
            }
            let validation = validateCandidate(trackId: candidateId, index: candidateIndex)
            if validation.track != nil { return candidateIndex }
            temporarilyFailedTrackIds.insert(candidateId)
            print("[NativeQueue] skipping invalid recovery candidate id=\(candidateId) reason=\(validation.code)")
        }
        return nil
    }

    private func clearStaleTransitionIfNeeded() {
        guard isTransitioningTrack, let startedAt = activeTransitionStartedAt else { return }
        if Date().timeIntervalSince(startedAt) > transitionTimeoutSeconds {
            print("[NativeQueue] transition timeout activeRequestId=\(activeTransitionRequestId ?? "nil") source=\(activeTransitionSource ?? "nil")")
            isTransitioningTrack = false
            activeTransitionRequestId = nil
            activeTransitionSource = nil
            activeTransitionStartedAt = nil
        }
    }

    private func endTransition(requestId: String, direction: String) {
        if activeTransitionRequestId == requestId {
            isTransitioningTrack = false
            activeTransitionRequestId = nil
            activeTransitionSource = nil
            activeTransitionStartedAt = nil
        }
        print("[NativeQueue] \(direction) EXIT requestId=\(requestId)")
    }

    private func playbackFileInfo(path: String) -> (exists: Bool, size: Int64) {
        guard FileManager.default.fileExists(atPath: path) else { return (false, 0) }
        let size = Int64((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return (true, size)
    }

    private func handleTrackFinished(_ track: NativeTrack) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.emit("progressChanged", self.engine.playbackState(queue: self.queueManager.dictionary))
            let requestId = self.nextRequestId(prefix: "auto-next")
            print("[NativeQueue] manual next requested requestId=\(requestId) source=auto-next")
            let nextIndex = self.queueManager.currentIndex + 1
            if nextIndex >= 0, nextIndex < self.queueManager.trackIds.count {
                _ = self.loadCandidate(at: nextIndex, requestId: requestId, source: "auto-next", shouldRestartLoadedTrack: true, allowRecovery: true)
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
