import AVFoundation
import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

final class NativeTrackImporter: NSObject, UIDocumentPickerDelegate {
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

    init(repository: NativeTrackRepository = NativeTrackRepository()) {
        self.repository = repository
        super.init()
    }

    func importTracks(from presenter: UIViewController, completion: @escaping (Result<[NativeTrack], Error>) -> Void) {
        self.completion = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: false)
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
        let metadata = readMetadata(from: asset)
        let audioProperties = readAudioProperties(from: asset, sizeBytes: copiedSizeBytes, fileExtension: copiedURL.pathExtension.lowercased())
        let durationMs = durationMs(for: asset)
        let now = Date()
        let bookmarkData = try? copiedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let stableId = stableId(originalFileName: sourceURL.lastPathComponent, sizeBytes: copiedSizeBytes, durationMs: durationMs)
        let albumArtUri = try saveArtworkIfPresent(metadata.artworkData, stableId: stableId)
        let fileName = copiedURL.lastPathComponent
        let fileExtension = copiedURL.pathExtension.lowercased()
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent

        let track = NativeTrack(
            id: UUID().uuidString,
            stableId: stableId,
            title: metadata.title?.nilIfBlank ?? fallbackTitle,
            artist: metadata.artist?.nilIfBlank,
            album: metadata.album?.nilIfBlank,
            durationMs: durationMs,
            fileName: fileName,
            fileExtension: fileExtension,
            codec: audioProperties.codec,
            sourceUri: sourceURL.absoluteString,
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
        logImportedMetadata(title: metadata.title?.nilIfBlank ?? fallbackTitle, properties: audioProperties, fileExtension: fileExtension)
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
        let metadata = asset.commonMetadata
        let title = firstStringValue(in: metadata, for: .commonIdentifierTitle)
        let artist = firstStringValue(in: metadata, for: .commonIdentifierArtist)
        let album = firstStringValue(in: metadata, for: .commonIdentifierAlbumName)
        let artworkData = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue
        return (title, artist, album, artworkData)
    }

    private func firstStringValue(in metadata: [AVMetadataItem], for identifier: AVMetadataIdentifier) -> String? {
        AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first?.stringValue
    }

    private func readAudioProperties(from asset: AVURLAsset, sizeBytes: Int64, fileExtension: String) -> (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?, codec: String?) {
        guard let track = asset.tracks(withMediaType: .audio).first else {
            return (nil, nil, nil, nil, normalizedCodec(for: nil, fileExtension: fileExtension))
        }

        var sampleRate: Int?
        var bitDepth: Int?
        var channelCount: Int?
        var codec: String?
        for formatDescription in track.formatDescriptions {
            guard let audioFormatDescription = formatDescription as? CMAudioFormatDescription,
                  let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription) else {
                continue
            }
            sampleRate = Int(audioDescription.pointee.mSampleRate.rounded())
            bitDepth = normalizedBitDepth(Int(audioDescription.pointee.mBitsPerChannel))
            channelCount = Int(audioDescription.pointee.mChannelsPerFrame)
            codec = normalizedCodec(for: fourCharCode(audioDescription.pointee.mFormatID), fileExtension: fileExtension)
            break
        }

        let seconds = CMTimeGetSeconds(asset.duration)
        let bitrate = seconds.isFinite && seconds > 0 ? Int(Double(sizeBytes * 8) / seconds) : nil
        return (sampleRate, bitDepth, bitrate, channelCount == 0 ? nil : channelCount, codec)
    }

    private func normalizedBitDepth(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return value
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
            case "wav", "wave", "aif", "aiff", "aifc": return "lpcm"
            case "flac": return "flac"
            case "alac": return "alac"
            case "mp3": return "mp3"
            case "aac": return "aac"
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
        guard let sampleRate = sampleRate else { return false }
        if let bitDepth = bitDepth, bitDepth >= 24 && sampleRate >= 48_000 {
            return true
        }
        guard bitDepth == nil, sampleRate >= 88_200 else { return false }
        let losslessTokens = ["lpcm", "alac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf"]
        let lossyTokens = ["mp3", "aac", "mp4a", "m4a", "mp4", "ogg", "opus"]
        let codecToken = codec?.lowercased()
        if let codecToken = codecToken, lossyTokens.contains(codecToken) { return false }
        if let codecToken = codecToken, losslessTokens.contains(codecToken) { return true }
        let extensionToken = fileExtension.lowercased()
        return losslessTokens.contains(extensionToken) && !lossyTokens.contains(extensionToken)
    }

    private func logImportedMetadata(title: String, properties: (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?, codec: String?), fileExtension: String) {
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
        guard let data = data, !data.isEmpty else { return nil }
        let fileURL = artworkDirectory.appendingPathComponent("\(stableId).artwork")
        try data.write(to: fileURL, options: [.atomic])
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
