import AVFoundation
import CryptoKit
import Foundation
import UIKit

final class NativeTrackImporter: NSObject, UIDocumentPickerDelegate {
    private static let audioDocumentTypes = [
        "public.audio",
        "public.mp3",
        "public.mpeg-4-audio",
        "com.apple.m4a-audio",
        "com.apple.protected-mpeg-4-audio",
        "org.xiph.flac",
        "com.microsoft.waveform-audio",
        "public.aifc-audio",
        "public.aiff-audio",
    ]

    private let repository: NativeTrackRepository
    private var completion: ((Result<[NativeTrack], Error>) -> Void)?

    private lazy var audioLibraryDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("AudioLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private lazy var artworkDirectory: URL = {
        let directory = audioLibraryDirectory.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private lazy var optimizedDirectory: URL = {
        let directory = audioLibraryDirectory.appendingPathComponent("Optimized", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    init(repository: NativeTrackRepository = NativeTrackRepository()) {
        self.repository = repository
        super.init()
    }

    func importTracks(from presenter: UIViewController, completion: @escaping (Result<[NativeTrack], Error>) -> Void) {
        self.completion = completion
        let picker = UIDocumentPickerViewController(documentTypes: Self.audioDocumentTypes, in: .open)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(.success([]))
        completion = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var importedTracks: [NativeTrack] = []
            for url in urls {
                do {
                    let track = try self.importSingleTrack(from: url)
                    let savedTrack = try self.repository.save(track)
                    self.removeDuplicateSandboxCopyIfNeeded(importedTrack: track, savedTrack: savedTrack)
                    importedTracks.append(savedTrack)
                } catch {
                    NSLog("NativeTrackImporter failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.completion?(.success(importedTracks))
                self?.completion = nil
            }
        }
    }

    private func importSingleTrack(from sourceURL: URL) throws -> NativeTrack {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let originalSizeBytes = Int64(resourceValues.fileSize ?? 0)
        let copiedURL = try copyIntoAudioLibrary(sourceURL)
        let copiedSizeBytes = Int64((try? copiedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int(originalSizeBytes))
        let asset = AVURLAsset(url: copiedURL)
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
        let metadata = readMetadata(from: asset)
        let audioProperties = readAudioProperties(from: asset, sizeBytes: copiedSizeBytes, fileExtension: copiedURL.pathExtension.lowercased())
        let durationMs = durationMs(for: asset)
        let now = Date()
        let bookmarkData = try? copiedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let stableId = stableId(originalFileName: sourceURL.lastPathComponent, sizeBytes: copiedSizeBytes, durationMs: durationMs)
        let albumArtUri = try saveArtworkIfPresent(metadata.artworkData, stableId: stableId)
        let fileName = copiedURL.lastPathComponent
        let fileExtension = copiedURL.pathExtension.lowercased()
        let resolvedTitle = metadata.title?.nilIfBlank ?? fallbackTitle
        let optimization = optimizeForPlaybackIfNeeded(
            sourceURL: copiedURL,
            stableId: stableId,
            title: resolvedTitle,
            properties: audioProperties,
            fileExtension: fileExtension
        )

        let track = NativeTrack(
            id: UUID().uuidString,
            stableId: stableId,
            title: resolvedTitle,
            artist: metadata.artist?.nilIfBlank,
            album: metadata.album?.nilIfBlank,
            durationMs: durationMs,
            fileName: fileName,
            fileExtension: fileExtension,
            codec: audioProperties.codec,
            qualityClass: qualityClass(sampleRate: audioProperties.sampleRate, bitDepth: audioProperties.bitDepth, bitrate: audioProperties.bitrate, codec: audioProperties.codec, fileExtension: fileExtension),
            sourceUri: sourceURL.absoluteString,
            originalUrl: copiedURL.path,
            playbackUrl: optimization.playbackURL?.path,
            optimizedUrl: optimization.optimizedURL?.path,
            optimizedForPlayback: optimization.optimizedForPlayback,
            optimizationStatus: optimization.status,
            optimizationError: optimization.error,
            originalBitDepth: audioProperties.bitDepth,
            originalSampleRate: audioProperties.sampleRate,
            originalBitrate: audioProperties.bitrate,
            originalFormat: fileExtension,
            bookmarkData: bookmarkData,
            localFilePath: copiedURL.path,
            sourceType: NativeTrackSourceType.manualIOS.rawValue,
            addedAt: now,
            updatedAt: now,
            sizeBytes: copiedSizeBytes,
            sampleRate: audioProperties.sampleRate,
            bitDepth: audioProperties.bitDepth,
            bitrate: audioProperties.bitrate,
            channelCount: audioProperties.channelCount,
            albumArtUri: albumArtUri,
            isAvailable: FileManager.default.fileExists(atPath: copiedURL.path),
            playCount: 0,
            lastPlayedAt: nil
        )
        logImportedMetadata(title: resolvedTitle, properties: audioProperties, fileExtension: fileExtension)
        return track
    }

    private func removeDuplicateSandboxCopyIfNeeded(importedTrack: NativeTrack, savedTrack: NativeTrack) {
        guard importedTrack.id != savedTrack.id else { return }
        if let localFilePath = importedTrack.localFilePath, localFilePath != savedTrack.localFilePath {
            try? FileManager.default.removeItem(atPath: localFilePath)
        }
        if let albumArtUri = importedTrack.albumArtUri, albumArtUri != savedTrack.albumArtUri {
            try? FileManager.default.removeItem(atPath: albumArtUri)
        }
        if let optimizedUrl = importedTrack.optimizedUrl, optimizedUrl != savedTrack.optimizedUrl {
            try? FileManager.default.removeItem(atPath: optimizedUrl)
        }
    }


    private func optimizeForPlaybackIfNeeded(
        sourceURL: URL,
        stableId: String,
        title: String,
        properties: (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?, codec: String?),
        fileExtension: String
    ) -> (playbackURL: URL?, optimizedURL: URL?, optimizedForPlayback: Bool, status: String, error: String?) {
        NSLog("[ImportOptimizer] original metadata id=\(stableId) title=\(title) bitDepth=\(properties.bitDepth.map(String.init) ?? "unknown") sampleRate=\(properties.sampleRate.map(String.init) ?? "unknown") bitrate=\(properties.bitrate.map(String.init) ?? "unknown") format=\(properties.codec ?? fileExtension)")
        let needsOptimization = (properties.bitDepth ?? 0) > 16 || (properties.sampleRate ?? 0) > 44_100
        NSLog("[ImportOptimizer] needs optimization \(needsOptimization)")
        guard needsOptimization else {
            let originalInfo = fileInfo(at: sourceURL)
            NSLog("[ImportOptimizer] optimized output url=\(sourceURL.path)")
            NSLog("[ImportOptimizer] output file exists \(originalInfo.exists)")
            NSLog("[ImportOptimizer] output file size bytes=\(originalInfo.size)")
            guard originalInfo.exists, originalInfo.size > 0 else {
                return (nil, nil, false, "failed", "Original copied audio file is missing or empty")
            }
            return (sourceURL, nil, false, "ready", nil)
        }

        let optimizedURL = optimizedDirectory.appendingPathComponent("\(stableId)-16bit-44100-stereo.caf")
        let temporaryURL = optimizedDirectory.appendingPathComponent("\(stableId)-16bit-44100-stereo.tmp.caf")
        NSLog("[ImportOptimizer] optimized output url=\(optimizedURL.path)")

        if FileManager.default.fileExists(atPath: optimizedURL.path) {
            let cachedInfo = fileInfo(at: optimizedURL)
            NSLog("[ImportOptimizer] output file exists \(cachedInfo.exists)")
            NSLog("[ImportOptimizer] output file size bytes=\(cachedInfo.size)")
            if cachedInfo.exists, cachedInfo.size > 0 {
                do {
                    try validateOptimizedOutput(at: optimizedURL)
                    NSLog("[ImportOptimizer] cache hit \(optimizedURL.path)")
                    return (optimizedURL, optimizedURL, true, "ready", nil)
                } catch {
                    NSLog("[ImportOptimizer] cache invalid error=\(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: optimizedURL)
                }
            }
        } else {
            NSLog("[ImportOptimizer] output file exists false")
            NSLog("[ImportOptimizer] output file size bytes=0")
        }

        do {
            try? FileManager.default.removeItem(at: temporaryURL)
            NSLog("[ImportOptimizer] conversion start \(sourceURL.path) -> \(temporaryURL.path)")
            try convertToOptimizedCAF(sourceURL: sourceURL, destinationURL: temporaryURL)
            let temporaryInfo = fileInfo(at: temporaryURL)
            NSLog("[ImportOptimizer] output file exists \(temporaryInfo.exists)")
            NSLog("[ImportOptimizer] output file size bytes=\(temporaryInfo.size)")
            guard temporaryInfo.exists, temporaryInfo.size > 0 else {
                throw NSError(domain: "ImportOptimizer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Optimized temporary output file is missing or empty"])
            }
            try validateOptimizedOutput(at: temporaryURL)
            try? FileManager.default.removeItem(at: optimizedURL)
            try FileManager.default.moveItem(at: temporaryURL, to: optimizedURL)
            let outputInfo = fileInfo(at: optimizedURL)
            NSLog("[ImportOptimizer] output file exists \(outputInfo.exists)")
            NSLog("[ImportOptimizer] output file size bytes=\(outputInfo.size)")
            guard outputInfo.exists, outputInfo.size > 0 else {
                throw NSError(domain: "ImportOptimizer", code: 9, userInfo: [NSLocalizedDescriptionKey: "Optimized final output file is missing or empty"])
            }
            try validateOptimizedOutput(at: optimizedURL)
            NSLog("[ImportOptimizer] conversion success \(optimizedURL.path)")
            return (optimizedURL, optimizedURL, true, "ready", nil)
        } catch {
            NSLog("[ImportOptimizer] conversion failed error=\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: temporaryURL)
            try? FileManager.default.removeItem(at: optimizedURL)
            return (nil, nil, false, "failed", error.localizedDescription)
        }
    }

    private func fileInfo(at url: URL) -> (exists: Bool, size: Int64) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (false, 0)
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return (true, Int64(size))
    }


    private func validateOptimizedOutput(at url: URL) throws {
        let outputFile = try AVAudioFile(forReading: url)
        guard outputFile.length > 0 else {
            throw NSError(domain: "ImportOptimizer", code: 9, userInfo: [NSLocalizedDescriptionKey: "Optimized output has no playable frames"])
        }
        let format = outputFile.processingFormat
        guard Int(format.sampleRate.rounded()) == 44_100, format.channelCount == 2 else {
            throw NSError(domain: "ImportOptimizer", code: 10, userInfo: [NSLocalizedDescriptionKey: "Optimized output format is not 44.1kHz stereo"])
        }
    }

    private func convertToOptimizedCAF(sourceURL: URL, destinationURL: URL) throws {
        try? FileManager.default.removeItem(at: destinationURL)
        let inputFile = try AVAudioFile(forReading: sourceURL)
        guard inputFile.processingFormat.sampleRate > 0, inputFile.processingFormat.channelCount > 0 else {
            throw NSError(domain: "ImportOptimizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid source audio format"])
        }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true),
              let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw NSError(domain: "ImportOptimizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create 16-bit/44.1kHz/stereo converter"])
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outputFile = try AVAudioFile(forWriting: destinationURL, settings: outputSettings, commonFormat: .pcmFormatInt16, interleaved: true)
        let inputCapacity: AVAudioFrameCount = 4096

        while true {
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inputCapacity) else {
                throw NSError(domain: "ImportOptimizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate converter input buffer"])
            }
            try inputFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 {
                try drainConverter(converter, outputFormat: outputFormat, outputFile: outputFile, frameCapacity: inputCapacity)
                break
            }

            var didProvideInput = false
            while true {
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputCapacity) else {
                    throw NSError(domain: "ImportOptimizer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate converter output buffer"])
                }
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if didProvideInput {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    didProvideInput = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                if let conversionError = conversionError { throw conversionError }
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
                if status == .inputRanDry || status == .endOfStream || status == .error {
                    if status == .error {
                        throw NSError(domain: "ImportOptimizer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"])
                    }
                    break
                }
            }
        }
    }


    private func drainConverter(
        _ converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        outputFile: AVAudioFile,
        frameCapacity: AVAudioFrameCount
    ) throws {
        var didSendEndOfStream = false
        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
                throw NSError(domain: "ImportOptimizer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate converter drain buffer"])
            }
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if didSendEndOfStream {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didSendEndOfStream = true
                outStatus.pointee = .endOfStream
                return nil
            }
            if let conversionError = conversionError { throw conversionError }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            if status == .endOfStream || status == .inputRanDry {
                break
            }
            if status == .error {
                throw NSError(domain: "ImportOptimizer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Audio conversion drain failed"])
            }
        }
    }

    private func copyIntoAudioLibrary(_ sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let originalExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent.sanitizedFileName
        let uniqueName = "\(baseName)-\(UUID().uuidString).\(originalExtension)"
        let destinationURL = audioLibraryDirectory.appendingPathComponent(uniqueName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func durationMs(for asset: AVURLAsset) -> Int64 {
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, !seconds.isNaN, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    private func readMetadata(from asset: AVURLAsset) -> (title: String?, artist: String?, album: String?, artworkData: Data?) {
        let metadataGroups = [asset.commonMetadata, asset.metadata] + asset.availableMetadataFormats.map { asset.metadata(forFormat: $0) }
        let items = metadataGroups.flatMap { $0 }
        let title = firstMetadataString(in: items, identifiers: [.commonIdentifierTitle], keys: ["title", "tit2", "©nam", "name", "songName"])
        let artist = firstMetadataString(in: items, identifiers: [.commonIdentifierArtist], keys: ["artist", "tpe1", "©art", "author", "performer"])
        let album = firstMetadataString(in: items, identifiers: [.commonIdentifierAlbumName], keys: ["album", "talb", "©alb", "albumName"])
        let artworkData = firstArtworkData(in: items)
        return (title, artist, album, artworkData)
    }

    private func firstMetadataString(in items: [AVMetadataItem], identifiers: [AVMetadataIdentifier], keys: [String]) -> String? {
        for identifier in identifiers {
            if let value = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first?.stringValue?.nilIfBlank {
                return value
            }
        }
        let normalizedKeys = Set(keys.map { $0.lowercased() })
        for item in items {
            let keyCandidates = [
                item.commonKey?.rawValue,
                item.identifier?.rawValue,
                item.key as? String,
                item.key.map { String(describing: $0) },
            ].compactMap { $0?.lowercased() }
            guard keyCandidates.contains(where: { candidate in normalizedKeys.contains(where: { candidate.contains($0) }) }) else { continue }
            if let value = item.stringValue?.nilIfBlank { return value }
            if let value = item.value as? String, let clean = value.nilIfBlank { return clean }
        }
        return nil
    }

    private func firstArtworkData(in items: [AVMetadataItem]) -> Data? {
        let artworkCandidates = items.filter { item in
            if item.identifier == .commonIdentifierArtwork { return true }
            let keyCandidates = [
                item.commonKey?.rawValue,
                item.identifier?.rawValue,
                item.key as? String,
                item.key.map { String(describing: $0) },
            ].compactMap { $0?.lowercased() }
            return keyCandidates.contains { $0.contains("artwork") || $0.contains("apic") || $0.contains("covr") || $0.contains("cover") }
        }
        for item in artworkCandidates {
            if let data = item.dataValue, !data.isEmpty { return data }
            if let data = item.value as? Data, !data.isEmpty { return data }
            if let dictionary = item.value as? [String: Any], let data = dictionary["data"] as? Data, !data.isEmpty { return data }
        }
        return nil
    }

    private func readAudioProperties(
        from asset: AVURLAsset,
        sizeBytes: Int64,
        fileExtension: String
    ) -> (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?, codec: String?) {
        var sampleRate: Int?
        var bitDepth: Int?
        var channelCount: Int?
        var codec: String?

        if let file = try? AVAudioFile(forReading: asset.url) {
            let description = file.fileFormat.streamDescription.pointee
            sampleRate = Int(description.mSampleRate.rounded())
            bitDepth = normalizedBitDepth(Int(description.mBitsPerChannel), commonFormat: file.fileFormat.commonFormat)
            channelCount = Int(description.mChannelsPerFrame)
            codec = normalizedCodec(for: fourCharCode(description.mFormatID), fileExtension: fileExtension)
        }

        if sampleRate == nil || bitDepth == nil || channelCount == nil || codec == nil {
            if let track = asset.tracks(withMediaType: .audio).first {
                for formatDescription in track.formatDescriptions {
                    let audioFormatDescription = formatDescription as! CMAudioFormatDescription

                    guard let audioDescription =
                        CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription) else {
                        continue
                    }

                    sampleRate = Int(audioDescription.pointee.mSampleRate.rounded())
                    bitDepth = normalizedBitDepth(Int(audioDescription.pointee.mBitsPerChannel))
                    channelCount = Int(audioDescription.pointee.mChannelsPerFrame)
                    codec = normalizedCodec(
                        for: fourCharCode(audioDescription.pointee.mFormatID),
                        fileExtension: fileExtension
                    )
                    break
                }
            }
        }

        let seconds = CMTimeGetSeconds(asset.duration)
        let bitrate = seconds.isFinite && seconds > 0 ? Int(Double(sizeBytes * 8) / seconds) : nil
        return (sampleRate, bitDepth, bitrate, channelCount == 0 ? nil : channelCount, codec ?? normalizedCodec(for: nil, fileExtension: fileExtension))
    }

    private func normalizedBitDepth(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return value
    }

    private func normalizedBitDepth(_ value: Int, commonFormat: AVAudioCommonFormat?) -> Int? {
        if value > 0 { return value }
        switch commonFormat {
        case .pcmFormatFloat32: return 32
        case .pcmFormatFloat64: return 64
        case .pcmFormatInt16: return 16
        case .pcmFormatInt32: return 32
        default: return nil
        }
    }

    private func normalizedCodec(for formatCode: String?, fileExtension: String) -> String? {
        let normalizedFormat = formatCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedFormat {
        case "lpcm": return "lpcm"
        case "alac": return "alac"
        case "flac": return "flac"
        case "mp3", ".mp3": return "mp3"
        case "aac", "aac ", "mp4a": return "aac"
        default:
            switch fileExtension.lowercased() {
            case "wav", "wave", "aif", "aiff", "aifc", "caf": return "lpcm"
            case "flac": return "flac"
            case "alac": return "alac"
            case "mp3": return "mp3"
            case "aac", "m4a", "mp4", "m4b": return "aac"
            default: return normalizedFormat?.nilIfBlank ?? fileExtension.lowercased().nilIfBlank
            }
        }
    }

    private func fourCharCode(_ value: AudioFormatID) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }

    private func isHiResMetadata(sampleRate: Int?, bitDepth: Int?, codec: String?, fileExtension: String) -> Bool {
        qualityClass(sampleRate: sampleRate, bitDepth: bitDepth, bitrate: nil, codec: codec, fileExtension: fileExtension) == "hi-res" ||
        qualityClass(sampleRate: sampleRate, bitDepth: bitDepth, bitrate: nil, codec: codec, fileExtension: fileExtension) == "studio"
    }

    private func qualityClass(sampleRate: Int?, bitDepth: Int?, bitrate: Int?, codec: String?, fileExtension: String) -> String {
        let sampleRateValue = sampleRate ?? 0
        let bitDepthValue = bitDepth ?? 0
        let codecToken = codec?.lowercased()
        let extensionToken = fileExtension.lowercased()
        let losslessTokens = ["lpcm", "alac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf"]
        let lossyTokens = ["mp3", "aac", "mp4a", "m4a", "mp4", "ogg", "opus"]
        let isLossless = [codecToken, extensionToken].compactMap { $0 }.contains { losslessTokens.contains($0) }
        let isLossy = [codecToken, extensionToken].compactMap { $0 }.contains { lossyTokens.contains($0) }
        if bitDepthValue >= 32 && sampleRateValue >= 48_000 && isLossless { return "studio" }
        if bitDepthValue >= 24 && sampleRateValue >= 48_000 { return "hi-res" }
        if bitDepth == nil && sampleRateValue >= 88_200 && isLossless && !isLossy { return "hi-res" }
        if bitDepthValue == 16 && sampleRateValue == 44_100 { return "cd" }
        if isLossless { return "lossless" }
        if isLossy || (bitrate ?? 0) > 0 && bitDepth == nil { return "lossy" }
        if bitDepth != nil || sampleRate != nil || bitrate != nil { return "standard" }
        return "unknown"
    }

    private func logImportedMetadata(
        title: String,
        properties: (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?, codec: String?),
        fileExtension: String
    ) {
        NSLog("[iOS Metadata] title=\(title)")
        NSLog("[iOS Metadata] sampleRate=\(properties.sampleRate.map(String.init) ?? "unknown")")
        NSLog("[iOS Metadata] bitDepth=\(properties.bitDepth.map(String.init) ?? "unknown")")
        NSLog("[iOS Metadata] bitrate=\(properties.bitrate.map(String.init) ?? "unknown")")
        NSLog("[iOS Metadata] codec=\(properties.codec ?? fileExtension)")
        NSLog("[iOS Metadata] isHiRes=\(isHiResMetadata(sampleRate: properties.sampleRate, bitDepth: properties.bitDepth, codec: properties.codec, fileExtension: fileExtension))")
    }

    private func stableId(originalFileName: String, sizeBytes: Int64, durationMs: Int64) -> String {
        let seed = "manual-ios|\(originalFileName)|\(sizeBytes)|\(durationMs)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func saveArtworkIfPresent(_ data: Data?, stableId: String) throws -> String? {
        guard let data = data, !data.isEmpty, let image = UIImage(data: data) else { return nil }
        let imageData: Data
        let fileExtension: String
        if data.prefix(4).elementsEqual([UInt8(0x89), UInt8(0x50), UInt8(0x4e), UInt8(0x47)]), let pngData = image.pngData() {
            imageData = pngData
            fileExtension = "png"
        } else if let jpegData = image.jpegData(compressionQuality: 0.92) {
            imageData = jpegData
            fileExtension = "jpg"
        } else {
            return nil
        }
        let fileURL = artworkDirectory.appendingPathComponent("\(stableId).\(fileExtension)")
        try imageData.write(to: fileURL, options: [.atomic])
        return fileURL.path
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "track" : trimmed
    }
}
