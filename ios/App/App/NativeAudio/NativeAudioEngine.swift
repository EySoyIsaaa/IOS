import AVFoundation
import Foundation

final class NativeAudioEngine {
    enum EngineError: Error, LocalizedError {
        case missingLocalFilePath
        case fileUnavailable(String)
        case noLoadedTrack
        case noPlayableFrames
        case engineOpenFailed(String)
        case invalidAudioFile(String)
        case fileTooLarge(String)
        case bufferAllocationFailed(String)
        case decodeFailed(String)
        case audioFormatError(String)
        case decoderError(String)
        case engineStartError(String)

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
            case .engineOpenFailed(let message),
                 .invalidAudioFile(let message),
                 .fileTooLarge(let message),
                 .bufferAllocationFailed(let message),
                 .decodeFailed(let message),
                 .audioFormatError(let message),
                 .decoderError(let message),
                 .engineStartError(let message):
                return message
            }
        }

        var errorCode: String {
            switch self {
            case .missingLocalFilePath:
                return "playback_url_missing"
            case .fileUnavailable:
                return "playback_file_missing"
            case .noLoadedTrack:
                return "no_loaded_track"
            case .noPlayableFrames:
                return "no_playable_frames"
            case .engineOpenFailed:
                return "engine_open_failed"
            case .invalidAudioFile:
                return "decode_failed"
            case .fileTooLarge:
                return "file_too_large"
            case .bufferAllocationFailed:
                return "buffer_allocation_failed"
            case .decodeFailed, .decoderError, .audioFormatError:
                return "decode_failed"
            case .engineStartError:
                return "engine_start_failed"
            }
        }
    }

    private static let eqFrequencies: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
        800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
        12500, 16000, 20000,
    ]
    private static let eqGainRange: ClosedRange<Float> = -8...8
    private static let maxHeadroomDb: Float = 10
    private static let maxNativeReverbWetDryMix: Float = 55
    private static let maxConcertHallWetDryMix: Float = 45
    private static let maxFullBufferMemoryBytes: Int64 = 512 * 1024 * 1024
    private static let maxSafeDSPBitDepth = 24
    private static let maxSafeDSPSampleRate = 192_000.0

    var onTrackFinished: ((NativeTrack) -> Void)?

    private let engine = AVAudioEngine()
    private let epicenterDSP = EpicenterDSPBridge()
    private let eqNode = AVAudioUnitEQ(numberOfBands: NativeAudioEngine.eqFrequencies.count)
    private let reverbNode = AVAudioUnitReverb()
    private let concertHallNode = AVAudioUnitReverb()
    private let fallbackPlayerNode = AVAudioPlayerNode()
    private var sourceNode: AVAudioSourceNode?
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private var fallbackAudioFile: AVAudioFile?
    private var fallbackStartTime: AVAudioTime?
    private var fallbackStartFrame: AVAudioFramePosition = 0
    private var isFallbackPlayback = false
    private var loadedTrack: NativeTrack?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var isScheduled = false
    private var isPlaying = false
    private var scheduleToken = 0
    private var eqEnabled = false
    private var eqGains = Array(repeating: Float(0), count: NativeAudioEngine.eqFrequencies.count)
    private var reverbEnabled = false
    private var reverbAmount: Float = 0
    private var concertHallEnabled = false
    private var concertHallAmount: Float = 0

    var currentTrackId: String? {
        loadedTrack?.id
    }

    var isCurrentlyPlaying: Bool {
        isPlaying
    }

    init() {
        engine.attach(eqNode)
        engine.attach(reverbNode)
        engine.attach(fallbackPlayerNode)
        engine.attach(concertHallNode)
        configureEQNode()
        reverbNode.loadFactoryPreset(.mediumRoom)
        concertHallNode.loadFactoryPreset(.largeHall)
        reverbNode.bypass = true
        concertHallNode.bypass = true
        reverbNode.wetDryMix = 0
        concertHallNode.wetDryMix = 0
        engine.connect(eqNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: concertHallNode, format: nil)
        engine.connect(concertHallNode, to: engine.mainMixerNode, format: nil)
        engine.connect(fallbackPlayerNode, to: engine.mainMixerNode, format: nil)
        configureSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!)
        updateHeadroom()
        engine.prepare()
    }

    func load(track: NativeTrack, startAt seconds: Double = 0) throws {
        print("[AudioCompat] metadata completa id=\(track.id) title=\(track.title) codec=\(track.codec ?? "unknown") ext=\(track.originalFormat ?? track.fileExtension) originalSampleRate=\(track.originalSampleRate.map(String.init) ?? "unknown") originalBitDepth=\(track.originalBitDepth.map(String.init) ?? "unknown") originalBitrate=\(track.originalBitrate.map(String.init) ?? "unknown") channels=\(track.channelCount.map(String.init) ?? "unknown") size=\(track.sizeBytes) optimizationStatus=\(track.optimizationStatus)")
        print("[NativeAudioEngine] original metadata shown separately originalUrl=\(track.originalUrl ?? track.sourceUri)")
        guard track.optimizationStatus == "ready" else {
            print("[NativeAudioEngine] playback aborted safely optimizationStatus=\(track.optimizationStatus) error=\(track.optimizationError ?? "unknown")")
            throw EngineError.audioFormatError(track.optimizationError ?? "Track is not optimized for playback")
        }
        guard let localFilePath = track.playbackUrl, !localFilePath.isEmpty else {
            print("[NativeAudioEngine] playback aborted safely missing playbackUrl trackId=\(track.id)")
            throw EngineError.missingLocalFilePath
        }
        print("[NativeAudioEngine] using playbackUrl=\(localFilePath)")
        let inputInfo = fileInfo(path: localFilePath)
        print("[NativeAudioEngine] file exists \(inputInfo.exists) size=\(inputInfo.size)")
        guard inputInfo.exists else {
            print("[NativeAudioEngine] playback aborted safely playbackUrl missing path=\(localFilePath)")
            throw EngineError.fileUnavailable(localFilePath)
        }

        scheduleToken += 1
        if engine.isRunning {
            engine.pause()
        }
        fallbackPlayerNode.stop()
        isFallbackPlayback = false
        fallbackAudioFile = nil
        fallbackStartTime = nil
        fallbackStartFrame = 0

        do {
            try loadFullBufferForDSP(track: track, localFilePath: localFilePath, startAt: seconds)
        } catch let error as EngineError {
            print("[NativeAudioEngine] decode failed error=\(error.localizedDescription)")
            do {
                try loadFallbackWithoutDSP(track: track, localFilePath: localFilePath, startAt: seconds, cause: error)
            } catch let fallbackError as EngineError {
                throw fallbackError
            } catch {
                throw EngineError.decoderError(error.localizedDescription)
            }
        } catch {
            print("[NativeAudioEngine] decode failed error=\(error.localizedDescription)")
            do {
                try loadFallbackWithoutDSP(track: track, localFilePath: localFilePath, startAt: seconds, cause: error)
            } catch let fallbackError as EngineError {
                throw fallbackError
            } catch {
                throw EngineError.decoderError(error.localizedDescription)
            }
        }
    }

    private func loadFullBufferForDSP(track: NativeTrack, localFilePath: String, startAt seconds: Double) throws {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forReading: URL(fileURLWithPath: localFilePath),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            print("[NativeAudioEngine] open failed error=\(error.localizedDescription)")
            throw EngineError.engineOpenFailed(error.localizedDescription)
        }
        print("[NativeAudioEngine] open success")
        print("[NativeAudioEngine] fileFormat=\(file.fileFormat)")
        print("[NativeAudioEngine] processingFormat=\(file.processingFormat)")
        guard file.processingFormat.sampleRate > 0, file.processingFormat.channelCount > 0 else {
            throw EngineError.audioFormatError("Audio format is missing sample rate or channel count")
        }
        guard file.processingFormat.sampleRate <= NativeAudioEngine.maxSafeDSPSampleRate else {
            print("[AudioCompat] unsupported reason=processing sampleRate \(file.processingFormat.sampleRate) exceeds \(NativeAudioEngine.maxSafeDSPSampleRate)")
            throw EngineError.audioFormatError("Este archivo Hi-Res excede el formato soportado por el motor DSP actual.")
        }
        let estimatedMemoryBytes = estimatedDecodedMemoryBytes(for: file)
        let estimatedMemoryMB = Double(estimatedMemoryBytes) / 1024.0 / 1024.0
        print("[NativeAudioEngine] file sampleRate=\(file.processingFormat.sampleRate) channels=\(file.processingFormat.channelCount) estimatedMemoryMB=\(String(format: "%.1f", estimatedMemoryMB)) strategy=full-buffer")
        guard file.length > 0 else {
            throw EngineError.noPlayableFrames
        }
        guard file.length <= AVAudioFramePosition(UInt32.max) else {
            throw EngineError.fileTooLarge("Audio file has too many frames for a single decoded buffer")
        }
        guard estimatedMemoryBytes <= NativeAudioEngine.maxFullBufferMemoryBytes else {
            throw EngineError.fileTooLarge("Audio file requires \(String(format: "%.1f", estimatedMemoryMB)) MB decoded; limit is \(NativeAudioEngine.maxFullBufferMemoryBytes / 1024 / 1024) MB")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            print("[NativeAudioEngine] buffer allocation failed frames=\(file.length) format=\(file.processingFormat)")
            throw EngineError.bufferAllocationFailed("Unable to allocate decoded audio buffer")
        }
        do {
            try file.read(into: buffer)
        } catch {
            print("[NativeAudioEngine] decode failed error=\(error.localizedDescription)")
            throw EngineError.decoderError(error.localizedDescription)
        }
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
    }

    private func loadFallbackWithoutDSP(track: NativeTrack, localFilePath: String, startAt seconds: Double, cause: Error) throws {
        print("[NativeAudioEngine] fallback without DSP cause=\(cause.localizedDescription)")
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: URL(fileURLWithPath: localFilePath))
        } catch {
            print("[NativeAudioEngine] open failed error=\(error.localizedDescription)")
            throw EngineError.engineOpenFailed(error.localizedDescription)
        }
        print("[NativeAudioEngine] open success")
        print("[NativeAudioEngine] fileFormat=\(file.fileFormat)")
        print("[NativeAudioEngine] processingFormat=\(file.processingFormat)")
        guard file.processingFormat.sampleRate > 0, file.processingFormat.channelCount > 0, file.length > 0 else {
            throw EngineError.audioFormatError("Fallback audio format is not playable")
        }
        audioFile = file
        audioBuffer = nil
        audioFormat = file.processingFormat
        fallbackAudioFile = file
        isFallbackPlayback = true
        loadedTrack = track
        isPlaying = false
        isScheduled = false
        pausedFrame = framePosition(for: seconds, in: file)
        scheduledStartFrame = pausedFrame
        fallbackStartFrame = pausedFrame
        scheduleFallbackSegment(from: pausedFrame)
    }

    func play() throws {
        guard audioFile != nil else {
            throw EngineError.noLoadedTrack
        }
        if isFallbackPlayback {
            if !isScheduled {
                scheduleFallbackSegment(from: pausedFrame)
            }
            guard isScheduled else {
                throw EngineError.noPlayableFrames
            }
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    print("[NativeAudioEngine] engine start failed error=\(error.localizedDescription)")
                    throw EngineError.engineStartError(error.localizedDescription)
                }
            }
            fallbackPlayerNode.play()
            fallbackStartTime = fallbackPlayerNode.lastRenderTime
            fallbackStartFrame = pausedFrame
            isPlaying = true
            return
        }
        if !isScheduled {
            _ = try scheduleSegment(from: pausedFrame)
        }
        guard isScheduled else {
            throw EngineError.noPlayableFrames
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[NativeAudioEngine] engine start failed error=\(error.localizedDescription)")
                throw EngineError.engineStartError(error.localizedDescription)
            }
        }
        isPlaying = true
    }

    func pause() {
        guard audioFile != nil else { return }
        pausedFrame = currentFramePosition()
        isPlaying = false
        if isFallbackPlayback {
            fallbackPlayerNode.pause()
        }
        engine.pause()
    }

    func stop(clearTrack: Bool = false) {
        scheduleToken += 1
        fallbackPlayerNode.stop()
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
            fallbackAudioFile = nil
            isFallbackPlayback = false
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
        if isFallbackPlayback {
            fallbackPlayerNode.stop()
            scheduleFallbackSegment(from: targetFrame)
            if wasPlaying, isScheduled {
                if !engine.isRunning {
                    do {
                        try engine.start()
                    } catch {
                        print("[NativeAudioEngine] engine start failed error=\(error.localizedDescription)")
                        throw EngineError.engineStartError(error.localizedDescription)
                    }
                }
                fallbackPlayerNode.play()
                fallbackStartTime = fallbackPlayerNode.lastRenderTime
                fallbackStartFrame = targetFrame
                isPlaying = true
            }
            return
        }
        epicenterDSP.reset()
        _ = try scheduleSegment(from: targetFrame)
        if wasPlaying, isScheduled {
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    print("[NativeAudioEngine] engine start failed seek error=\(error.localizedDescription)")
                    throw EngineError.engineStartError(error.localizedDescription)
                }
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

    func setEqEnabled(_ enabled: Bool) -> [String: Any] {
        eqEnabled = enabled
        applyEQBands()
        updateHeadroom()
        return eqState()
    }

    func setEqBand(index: Int, gain: Double) -> [String: Any] {
        guard eqGains.indices.contains(index) else {
            return ["status": "error", "code": "invalid_eq_band", "message": "EQ band index is out of range"]
        }
        eqGains[index] = clampEqGain(Float(gain))
        applyEQBands()
        updateHeadroom()
        return eqState()
    }

    func setEqBands(_ gains: [Double]) -> [String: Any] {
        var next = Array(repeating: Float(0), count: NativeAudioEngine.eqFrequencies.count)
        for (index, gain) in gains.prefix(NativeAudioEngine.eqFrequencies.count).enumerated() {
            next[index] = clampEqGain(Float(gain))
        }
        eqGains = next
        applyEQBands()
        updateHeadroom()
        return eqState(extra: ["preset": NSNull()])
    }

    func setEqPreset(name: String?, gains: [Double]) -> [String: Any] {
        var state = setEqBands(gains)
        state["preset"] = jsonOrNull(name)
        return state
    }

    func resetEq() -> [String: Any] {
        eqGains = Array(repeating: 0, count: NativeAudioEngine.eqFrequencies.count)
        applyEQBands()
        updateHeadroom()
        return eqState()
    }

    func setReverbEnabled(_ enabled: Bool) -> [String: Any] {
        reverbEnabled = enabled
        applyReverbState()
        updateHeadroom()
        return fxState()
    }

    func setReverbAmount(_ amount: Double) -> [String: Any] {
        reverbAmount = clampPercent(Float(amount))
        applyReverbState()
        updateHeadroom()
        return fxState()
    }

    func setConcertHallEnabled(_ enabled: Bool) -> [String: Any] {
        concertHallEnabled = enabled
        applyConcertHallState()
        updateHeadroom()
        return fxState()
    }

    func setConcertHallAmount(_ amount: Double) -> [String: Any] {
        concertHallAmount = clampPercent(Float(amount))
        applyConcertHallState()
        updateHeadroom()
        return fxState()
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
            "eq": eqState(),
            "fx": fxState(),
        ]
        if let queue = queue {
            state["queue"] = queue
        }
        return state
    }


    private func fileInfo(path: String) -> (exists: Bool, size: Int64) {
        guard FileManager.default.fileExists(atPath: path) else { return (false, 0) }
        let size = Int64((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return (true, size)
    }

    private func configureEQNode() {
        for (index, band) in eqNode.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = NativeAudioEngine.eqFrequencies[index]
            band.bandwidth = 1.0 / 3.0
            band.gain = 0
            band.bypass = false
        }
        eqNode.globalGain = 0
        eqNode.bypass = true
    }

    private func applyEQBands() {
        eqNode.bypass = !eqEnabled
        for (index, band) in eqNode.bands.enumerated() {
            band.gain = eqEnabled ? eqGains[index] : 0
        }
        eqNode.globalGain = eqEnabled ? -eqHeadroomDb() : 0
    }

    private func applyReverbState() {
        reverbNode.bypass = !reverbEnabled || reverbAmount <= 0
        reverbNode.wetDryMix = reverbEnabled ? (reverbAmount / 100) * NativeAudioEngine.maxNativeReverbWetDryMix : 0
    }

    private func applyConcertHallState() {
        concertHallNode.bypass = !concertHallEnabled || concertHallAmount <= 0
        concertHallNode.wetDryMix = concertHallEnabled ? (concertHallAmount / 100) * NativeAudioEngine.maxConcertHallWetDryMix : 0
    }

    private func updateHeadroom() {
        let fxHeadroom = (reverbEnabled ? (reverbAmount / 100) * 3 : 0) + (concertHallEnabled ? (concertHallAmount / 100) * 4 : 0)
        let totalHeadroom = min(NativeAudioEngine.maxHeadroomDb, (eqEnabled ? eqHeadroomDb() : 0) + fxHeadroom)
        engine.mainMixerNode.outputVolume = powf(10, -totalHeadroom / 20)
    }

    private func eqHeadroomDb() -> Float {
        let positiveGains = eqGains.filter { $0 > 0 }
        guard !positiveGains.isEmpty else { return 0 }
        let maxBoost = positiveGains.max() ?? 0
        let averageBoost = positiveGains.reduce(0, +) / Float(positiveGains.count)
        let density = Float(positiveGains.count) / Float(eqGains.count)
        return min(8.0, (maxBoost * 0.45) + (averageBoost * density * 0.35))
    }

    private func eqState(extra: [String: Any] = [:]) -> [String: Any] {
        var state: [String: Any] = [
            "status": "ok",
            "enabled": eqEnabled,
            "bands": eqGains.map { Double($0) },
            "frequencies": NativeAudioEngine.eqFrequencies.map { Double($0) },
            "headroomDb": Double(eqEnabled ? eqHeadroomDb() : 0),
        ]
        for (key, value) in extra { state[key] = value }
        return state
    }

    private func fxState() -> [String: Any] {
        [
            "status": "ok",
            "reverbEnabled": reverbEnabled,
            "reverbAmount": Double(reverbAmount),
            "reverbWetDryMix": Double(reverbNode.wetDryMix),
            "concertHallEnabled": concertHallEnabled,
            "concertHallAmount": Double(concertHallAmount),
            "concertHallWetDryMix": Double(concertHallNode.wetDryMix),
            "combinedMode": "serial_reverb_then_concert_hall",
            "outputVolume": Double(engine.mainMixerNode.outputVolume),
        ]
    }

    private func clampEqGain(_ gain: Float) -> Float {
        min(max(gain, NativeAudioEngine.eqGainRange.lowerBound), NativeAudioEngine.eqGainRange.upperBound)
    }

    private func clampPercent(_ value: Float) -> Float {
        min(max(value, 0), 100)
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
                destination.update(from: source, count: Int(framesToCopy))
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
        engine.connect(node, to: eqNode, format: format)
        epicenterDSP.prepare(withSampleRate: format.sampleRate, channelCount: Int(format.channelCount), maxFrames: 8192)
        print("[iOS Epicenter DSP] prepared sampleRate=\(format.sampleRate) channels=\(format.channelCount)")
        print("[iOS Epicenter DSP] depth calibration constants \(epicenterDSP.calibrationDictionary())")
    }

    private func estimatedDecodedMemoryBytes(for file: AVAudioFile) -> Int64 {
        let channels = max(Int64(file.processingFormat.channelCount), 1)
        let bytesPerSample = Int64(MemoryLayout<Float>.size)
        return max(file.length, 0) * channels * bytesPerSample
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

    private func scheduleFallbackSegment(from frame: AVAudioFramePosition) {
        guard let file = fallbackAudioFile else {
            isScheduled = false
            return
        }
        let clampedFrame = min(max(frame, 0), file.length)
        let remainingFrames = max(file.length - clampedFrame, 0)
        scheduledStartFrame = clampedFrame
        pausedFrame = clampedFrame
        fallbackStartFrame = clampedFrame
        scheduleToken += 1
        let token = scheduleToken
        guard remainingFrames > 0 else {
            isScheduled = false
            return
        }
        isScheduled = true
        fallbackPlayerNode.stop()
        fallbackPlayerNode.scheduleSegment(
            file,
            startingFrame: clampedFrame,
            frameCount: AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max))),
            at: nil
        ) { [weak self] in
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
        if isFallbackPlayback, isPlaying,
           let nodeTime = fallbackPlayerNode.lastRenderTime,
           let playerTime = fallbackPlayerNode.playerTime(forNodeTime: nodeTime) {
            return min(max(fallbackStartFrame + AVAudioFramePosition(playerTime.sampleTime), 0), file.length)
        }
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
