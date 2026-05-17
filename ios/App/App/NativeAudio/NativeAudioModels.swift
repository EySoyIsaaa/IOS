import Foundation

enum NativeAudioStubStatus: String {
    case notImplemented = "not_implemented"
}

enum NativeTrackSourceType: String {
    case manualIOS = "manual-ios"
}

struct NativeTrack {
    let id: String
    let stableId: String
    let title: String
    let artist: String?
    let album: String?
    let durationMs: Int64
    let fileName: String
    let fileExtension: String
    let codec: String?
    let qualityClass: String?
    let sourceUri: String
    let originalUrl: String?
    let playbackUrl: String?
    let optimizedUrl: String?
    let optimizedForPlayback: Bool
    let optimizationStatus: String
    let optimizationError: String?
    let originalBitDepth: Int?
    let originalSampleRate: Int?
    let originalBitrate: Int?
    let originalFormat: String?
    let bookmarkData: Data?
    let localFilePath: String?
    let sourceType: String
    let addedAt: Date
    let updatedAt: Date
    let sizeBytes: Int64
    let sampleRate: Int?
    let bitDepth: Int?
    let bitrate: Int?
    let channelCount: Int?
    let albumArtUri: String?
    let isAvailable: Bool
    let playCount: Int
    let lastPlayedAt: Date?

    var dictionary: [String: Any] {
        [
            "id": id,
            "stableId": stableId,
            "title": title,
            "artist": jsonOrNull(artist),
            "album": jsonOrNull(album),
            "durationMs": durationMs,
            "fileName": fileName,
            "fileExtension": fileExtension,
            "codec": jsonOrNull(codec),
            "qualityClass": jsonOrNull(qualityClass),
            "sourceUri": sourceUri,
            "sourceUrl": jsonOrNull(originalUrl ?? sourceUri),
            "originalUrl": jsonOrNull(originalUrl ?? sourceUri),
            "playbackUrl": jsonOrNull(playbackUrl),
            "optimizedUrl": jsonOrNull(optimizedUrl),
            "optimizedForPlayback": optimizedForPlayback,
            "optimizationStatus": optimizationStatus,
            "optimizationError": jsonOrNull(optimizationError),
            "originalBitDepth": jsonOrNull(originalBitDepth ?? bitDepth),
            "originalSampleRate": jsonOrNull(originalSampleRate ?? sampleRate),
            "originalBitrate": jsonOrNull(originalBitrate ?? bitrate),
            "originalFormat": jsonOrNull(originalFormat ?? fileExtension),
            "bookmarkData": jsonOrNull(bookmarkData?.base64EncodedString()),
            "localFilePath": jsonOrNull(localFilePath),
            "sourceType": sourceType,
            "addedAt": NativeTrack.dateFormatter.string(from: addedAt),
            "updatedAt": NativeTrack.dateFormatter.string(from: updatedAt),
            "sizeBytes": sizeBytes,
            "sampleRate": jsonOrNull(sampleRate),
            "bitDepth": jsonOrNull(bitDepth),
            "bitrate": jsonOrNull(bitrate),
            "channelCount": jsonOrNull(channelCount),
            "albumArtUri": jsonOrNull(albumArtUri),
            "isAvailable": isAvailable,
            "playCount": playCount,
            "lastPlayedAt": jsonOrNull(lastPlayedAt.map { NativeTrack.dateFormatter.string(from: $0) }),
        ]
    }

    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct NativeLibraryPage {
    let tracks: [NativeTrack]
    let offset: Int
    let limit: Int
    let total: Int

    var dictionary: [String: Any] {
        [
            "status": "ok",
            "tracks": tracks.map { $0.dictionary },
            "offset": offset,
            "limit": limit,
            "total": total,
        ]
    }
}

struct NativePlaybackStateStub {
    let isPlaying: Bool = false
    let currentTime: Double = 0
    let duration: Double = 0
    let currentTrackId: String? = nil

    var dictionary: [String: Any] {
        [
            "status": NativeAudioStubStatus.notImplemented.rawValue,
            "isPlaying": isPlaying,
            "currentTime": currentTime,
            "duration": duration,
            "currentTrackId": jsonOrNull(currentTrackId),
        ]
    }
}


private func jsonOrNull<T>(_ value: T?) -> Any {
    guard let value = value else {
        return NSNull()
    }
    return value
}
