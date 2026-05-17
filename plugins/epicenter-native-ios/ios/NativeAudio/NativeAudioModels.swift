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
    let sourceUri: String
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
            "qualityClass": audioQualityClass,
            "isHiRes": isHiResAudioQuality,
            "sourceUri": sourceUri,
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

    private var isHiResAudioQuality: Bool {
        guard let sampleRate = sampleRate, sampleRate > 0 else { return false }
        if let bitDepth = bitDepth, bitDepth > 0 {
            return bitDepth >= 24 && sampleRate >= 48_000
        }
        return sampleRate >= 88_200 && NativeTrack.losslessExtensions.contains(fileExtension.lowercased())
    }

    private var audioQualityClass: String {
        if isHiResAudioQuality { return "hi-res" }
        let lowerExtension = fileExtension.lowercased()
        if bitDepth == 16 && sampleRate == 44_100 { return "cd" }
        if NativeTrack.lossyExtensions.contains(lowerExtension) { return "lossy" }
        if NativeTrack.losslessExtensions.contains(lowerExtension) && (bitDepth != nil || sampleRate != nil) { return "lossless" }
        if bitDepth != nil || sampleRate != nil || bitrate != nil { return "standard" }
        return "unknown"
    }

    private static let losslessExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "alac", "caf"]
    private static let lossyExtensions: Set<String> = ["mp3", "aac", "m4a", "m4b", "ogg", "opus"]

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
