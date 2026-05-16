import AVFoundation
import CryptoKit
import Foundation
import UIKit

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
        let picker = UIDocumentPickerViewController(documentTypes: ["public.audio"], in: .import)
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
        let audioProperties = readAudioProperties(from: asset, sizeBytes: copiedSizeBytes)
        let durationMs = durationMs(for: asset)
        let now = Date()
        let bookmarkData = try? copiedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let stableId = stableId(originalFileName: sourceURL.lastPathComponent, sizeBytes: copiedSizeBytes, durationMs: durationMs)
        let albumArtUri = try saveArtworkIfPresent(metadata.artworkData, stableId: stableId)
        let fileName = copiedURL.lastPathComponent
        let fileExtension = copiedURL.pathExtension.lowercased()
        let fallbackTitle = copiedURL.deletingPathExtension().lastPathComponent

        return NativeTrack(
            id: UUID().uuidString,
            stableId: stableId,
            title: metadata.title?.nilIfBlank ?? fallbackTitle,
            artist: metadata.artist?.nilIfBlank,
            album: metadata.album?.nilIfBlank,
            durationMs: durationMs,
            fileName: fileName,
            fileExtension: fileExtension,
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

    private func readAudioProperties(from asset: AVURLAsset, sizeBytes: Int64) -> (sampleRate: Int?, bitDepth: Int?, bitrate: Int?, channelCount: Int?) {
        guard let track = asset.tracks(withMediaType: .audio).first else {
            return (nil, nil, nil, nil)
        }

        var sampleRate: Int?
        var bitDepth: Int?
        var channelCount: Int?
        for formatDescription in track.formatDescriptions {
            guard let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription as! CMAudioFormatDescription) else {
                continue
            }
            sampleRate = Int(audioDescription.pointee.mSampleRate.rounded())
            bitDepth = Int(audioDescription.pointee.mBitsPerChannel)
            channelCount = Int(audioDescription.pointee.mChannelsPerFrame)
            break
        }

        let seconds = CMTimeGetSeconds(asset.duration)
        let bitrate = seconds.isFinite && seconds > 0 ? Int(Double(sizeBytes * 8) / seconds) : nil
        return (sampleRate, bitDepth == 0 ? nil : bitDepth, bitrate, channelCount == 0 ? nil : channelCount)
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
