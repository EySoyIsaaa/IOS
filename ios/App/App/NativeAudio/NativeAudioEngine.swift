import AVFoundation
import Foundation

final class NativeAudioEngine {
    enum EngineError: Error, LocalizedError {
        case missingLocalFilePath
        case fileUnavailable(String)
        case noLoadedTrack
        case invalidAudioFile(String)

        var errorDescription: String? {
            switch self {
            case .missingLocalFilePath:
                return "Track does not have a local file path"
            case .fileUnavailable(let path):
                return "Audio file is not available at \(path)"
            case .noLoadedTrack:
                return "No track is loaded"
            case .invalidAudioFile(let message):
                return message
            }
        }
    }

    var onTrackFinished: ((NativeTrack) -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var loadedTrack: NativeTrack?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var isScheduled = false
    private var isPlaying = false
    private var scheduleToken = 0

    var currentTrackId: String? {
        loadedTrack?.id
    }

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }

    func load(track: NativeTrack, startAt seconds: Double = 0) throws {
        guard let localFilePath = track.localFilePath, !localFilePath.isEmpty else {
            throw EngineError.missingLocalFilePath
        }
        guard FileManager.default.fileExists(atPath: localFilePath) else {
            throw EngineError.fileUnavailable(localFilePath)
        }

        scheduleToken += 1
        playerNode.stop()
        if engine.isRunning {
            engine.pause()
        }

        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: localFilePath))
            audioFile = file
            loadedTrack = track
            isPlaying = false
            isScheduled = false
            pausedFrame = framePosition(for: seconds, in: file)
            scheduledStartFrame = pausedFrame
            try scheduleSegment(from: pausedFrame)
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.invalidAudioFile(error.localizedDescription)
        }
    }

    func play() throws {
        guard audioFile != nil else {
            throw EngineError.noLoadedTrack
        }
        if !isScheduled {
            try scheduleSegment(from: pausedFrame)
        }
        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        isPlaying = true
    }

    func pause() {
        guard audioFile != nil else { return }
        pausedFrame = currentFramePosition()
        playerNode.pause()
        isPlaying = false
    }

    func stop(clearTrack: Bool = false) {
        scheduleToken += 1
        playerNode.stop()
        engine.pause()
        isPlaying = false
        isScheduled = false
        pausedFrame = 0
        scheduledStartFrame = 0
        if clearTrack {
            loadedTrack = nil
            audioFile = nil
        }
    }

    func seek(to seconds: Double) throws {
        guard let file = audioFile else {
            throw EngineError.noLoadedTrack
        }
        let wasPlaying = isPlaying
        let targetFrame = framePosition(for: seconds, in: file)
        scheduleToken += 1
        playerNode.stop()
        isPlaying = false
        isScheduled = false
        pausedFrame = targetFrame
        try scheduleSegment(from: targetFrame)
        if wasPlaying {
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
            isPlaying = true
        }
    }

    func playbackState(queue: [String: Any]? = nil) -> [String: Any] {
        var state: [String: Any] = [
            "status": "ok",
            "isPlaying": isPlaying,
            "currentTime": currentTimeSeconds(),
            "duration": durationSeconds(),
            "durationMs": Int64((durationSeconds() * 1000).rounded()),
            "currentTrackId": jsonOrNull(loadedTrack?.id),
            "stableId": jsonOrNull(loadedTrack?.stableId),
            "currentTrack": jsonOrNull(loadedTrack?.dictionary),
        ]
        if let queue = queue {
            state["queue"] = queue
        }
        return state
    }

    private func scheduleSegment(from frame: AVAudioFramePosition) throws {
        guard let file = audioFile else {
            throw EngineError.noLoadedTrack
        }
        let clampedFrame = min(max(frame, 0), file.length)
        let remainingFrames = max(file.length - clampedFrame, 0)
        scheduledStartFrame = clampedFrame
        pausedFrame = clampedFrame
        isScheduled = true
        scheduleToken += 1
        let token = scheduleToken

        guard remainingFrames > 0 else {
            isScheduled = false
            return
        }

        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))
        playerNode.scheduleSegment(
            file,
            startingFrame: clampedFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePlaybackCompleted(token: token)
            }
        }
    }

    private func handlePlaybackCompleted(token: Int) {
        guard token == scheduleToken, isPlaying, let finishedTrack = loadedTrack else {
            return
        }
        isPlaying = false
        isScheduled = false
        pausedFrame = 0
        scheduledStartFrame = 0
        onTrackFinished?(finishedTrack)
    }

    private func currentTimeSeconds() -> Double {
        guard let file = audioFile else { return 0 }
        return Double(currentFramePosition()) / file.processingFormat.sampleRate
    }

    private func durationSeconds() -> Double {
        guard let file = audioFile else {
            return Double(loadedTrack?.durationMs ?? 0) / 1000.0
        }
        guard file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func currentFramePosition() -> AVAudioFramePosition {
        guard let file = audioFile else { return 0 }
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return min(max(pausedFrame, 0), file.length)
        }
        let currentFrame = scheduledStartFrame + AVAudioFramePosition(playerTime.sampleTime)
        return min(max(currentFrame, 0), file.length)
    }

    private func framePosition(for seconds: Double, in file: AVAudioFile) -> AVAudioFramePosition {
        let safeSeconds = max(seconds, 0)
        let targetFrame = AVAudioFramePosition((safeSeconds * file.processingFormat.sampleRate).rounded())
        return min(max(targetFrame, 0), file.length)
    }
}


private func jsonOrNull<T>(_ value: T?) -> Any {
    guard let value = value else {
        return NSNull()
    }
    return value
}
