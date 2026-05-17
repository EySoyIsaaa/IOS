import AVFoundation
import Foundation

final class NativeAudioEngine {
    enum EngineError: Error, LocalizedError {
        case missingLocalFilePath
        case fileUnavailable(String)
        case noLoadedTrack
        case noPlayableFrames
        case invalidAudioFile(String)

        var errorDescription: String? {
            switch self {
            case .missingLocalFilePath:
                return "Track does not have a local file path"
            case .fileUnavailable(let path):
                return "Audio file is not available at \(path)"
            case .noLoadedTrack:
                return "No track is loaded"
            case .noPlayableFrames:
                return "No playable audio frames remain for the loaded track"
            case .invalidAudioFile(let message):
                return message
            }
        }
    }

    var onTrackFinished: ((NativeTrack) -> Void)?

    private let engine = AVAudioEngine()
    private let epicenterDSP = EpicenterDSPBridge()
    private var sourceNode: AVAudioSourceNode?
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private var loadedTrack: NativeTrack?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var isScheduled = false
    private var isPlaying = false
    private var scheduleToken = 0

    var currentTrackId: String? {
        loadedTrack?.id
    }

    var isCurrentlyPlaying: Bool {
        isPlaying
    }

    init() {
        configureSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!)
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
        if engine.isRunning {
            engine.pause()
        }

        do {
            let file = try AVAudioFile(
                forReading: URL(fileURLWithPath: localFilePath),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw EngineError.invalidAudioFile("Unable to allocate decoded audio buffer")
            }
            try file.read(into: buffer)
            audioFile = file
            audioBuffer = buffer
            audioFormat = file.processingFormat
            configureSourceNode(format: file.processingFormat)
            epicenterDSP.prepare(withSampleRate: file.processingFormat.sampleRate, channelCount: Int(file.processingFormat.channelCount), maxFrames: 8192)
            epicenterDSP.reset()
            loadedTrack = track
            isPlaying = false
            isScheduled = false
            pausedFrame = framePosition(for: seconds, in: file)
            scheduledStartFrame = pausedFrame
            _ = try scheduleSegment(from: pausedFrame)
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
            _ = try scheduleSegment(from: pausedFrame)
        }
        guard isScheduled else {
            throw EngineError.noPlayableFrames
        }
        if !engine.isRunning {
            try engine.start()
        }
        isPlaying = true
    }

    func pause() {
        guard audioFile != nil else { return }
        pausedFrame = currentFramePosition()
        isPlaying = false
        engine.pause()
    }

    func stop(clearTrack: Bool = false) {
        scheduleToken += 1
        engine.pause()
        isPlaying = false
        isScheduled = false
        pausedFrame = 0
        scheduledStartFrame = 0
        epicenterDSP.reset()
        if clearTrack {
            loadedTrack = nil
            audioFile = nil
            audioBuffer = nil
            audioFormat = nil
        }
    }

    func seek(to seconds: Double) throws {
        guard let file = audioFile else {
            throw EngineError.noLoadedTrack
        }
        let wasPlaying = isPlaying
        let targetFrame = framePosition(for: seconds, in: file)
        scheduleToken += 1
        isPlaying = false
        isScheduled = false
        pausedFrame = targetFrame
        epicenterDSP.reset()
        _ = try scheduleSegment(from: targetFrame)
        if wasPlaying, isScheduled {
            if !engine.isRunning {
                try engine.start()
            }
            isPlaying = true
        }
    }


    func setEpicenterEnabled(_ enabled: Bool) -> [String: Any] {
        epicenterDSP.setEnabled(enabled)
        print("[iOS Epicenter DSP] enabled \(enabled)")
        return ["status": "ok", "epicenter": epicenterDSP.stateDictionary()]
    }

    func setEpicenterParams(intensity: Double?, sweepFreq: Double?, width: Double?, balance: Double?, volume: Double?) -> [String: Any] {
        let current = epicenterDSP.stateDictionary()
        let nextIntensity = Float(intensity ?? numberValue(current["intensity"], fallback: 100))
        let nextSweep = Float(sweepFreq ?? numberValue(current["sweepFreq"], fallback: 45))
        let nextWidth = Float(width ?? numberValue(current["width"], fallback: 50))
        let nextBalance = Float(balance ?? numberValue(current["balance"], fallback: 100))
        let nextVolume = Float(volume ?? numberValue(current["volume"], fallback: 100))
        epicenterDSP.setIntensity(nextIntensity, sweepFreq: nextSweep, width: nextWidth, balance: nextBalance, volume: nextVolume)
        print("[iOS Epicenter DSP] params intensity=\(nextIntensity) sweep=\(nextSweep) width=\(nextWidth) balance=\(nextBalance) volume=\(nextVolume)")
        return ["status": "ok", "epicenter": epicenterDSP.stateDictionary()]
    }

    var epicenterState: [String: Any] {
        epicenterDSP.stateDictionary()
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
            "epicenter": epicenterDSP.stateDictionary(),
        ]
        if let queue = queue {
            state["queue"] = queue
        }
        return state
    }


    private func configureSourceNode(format: AVAudioFormat) {
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
        }
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let output = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for index in 0..<output.count {
                memset(output[index].mData, 0, Int(output[index].mDataByteSize))
            }
            guard self.isPlaying,
                  let buffer = self.audioBuffer,
                  let sourceChannels = buffer.floatChannelData else {
                return noErr
            }

            let startFrame = self.pausedFrame
            if startFrame >= AVAudioFramePosition(buffer.frameLength) {
                let token = self.scheduleToken
                DispatchQueue.main.async { [weak self] in
                    self?.handlePlaybackCompleted(token: token)
                }
                return noErr
            }

            let availableFrames = AVAudioFrameCount(max(0, AVAudioFramePosition(buffer.frameLength) - startFrame))
            let framesToCopy = min(frameCount, availableFrames)
            let startIndex = Int(startFrame)
            let sourceChannelCount = Int(buffer.format.channelCount)
            let outputChannelCount = output.count
            var leftPointer: UnsafeMutablePointer<Float>?
            var rightPointer: UnsafeMutablePointer<Float>?

            for channel in 0..<outputChannelCount {
                guard let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let sourceIndex = min(channel, max(0, sourceChannelCount - 1))
                let source = sourceChannels[sourceIndex].advanced(by: startIndex)
                destination.assign(from: source, count: Int(framesToCopy))
                if channel == 0 { leftPointer = destination }
                if channel == 1 { rightPointer = destination }
            }

            if let leftPointer = leftPointer {
                self.epicenterDSP.processLeft(leftPointer, right: rightPointer, frameCount: Int(framesToCopy))
            }

            self.pausedFrame = startFrame + AVAudioFramePosition(framesToCopy)
            if framesToCopy < frameCount || self.pausedFrame >= AVAudioFramePosition(buffer.frameLength) {
                let token = self.scheduleToken
                DispatchQueue.main.async { [weak self] in
                    self?.handlePlaybackCompleted(token: token)
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        epicenterDSP.prepare(withSampleRate: format.sampleRate, channelCount: Int(format.channelCount), maxFrames: 8192)
        print("[iOS Epicenter DSP] prepared sampleRate=\(format.sampleRate) channels=\(format.channelCount)")
        print("[iOS Epicenter DSP] depth calibration constants \(epicenterDSP.calibrationDictionary())")
    }

    private func scheduleSegment(from frame: AVAudioFramePosition) throws -> Bool {
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
            return false
        }

        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))
        _ = frameCount
        _ = token
        return true
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
        return min(max(pausedFrame, 0), file.length)
    }

    private func framePosition(for seconds: Double, in file: AVAudioFile) -> AVAudioFramePosition {
        let safeSeconds = max(seconds, 0)
        let targetFrame = AVAudioFramePosition((safeSeconds * file.processingFormat.sampleRate).rounded())
        return min(max(targetFrame, 0), file.length)
    }
}


private func numberValue(_ value: Any?, fallback: Double) -> Double {
    if let value = value as? NSNumber {
        return value.doubleValue
    }
    if let value = value as? Double {
        return value
    }
    if let value = value as? Float {
        return Double(value)
    }
    return fallback
}

private func jsonOrNull<T>(_ value: T?) -> Any {
    guard let value = value else {
        return NSNull()
    }
    return value
}
