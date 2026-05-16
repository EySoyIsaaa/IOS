import Foundation

final class NativeTrackRepository {
    private let database: NativeLibraryDatabase

    init(database: NativeLibraryDatabase = .shared) {
        self.database = database
    }

    func save(_ track: NativeTrack) throws -> NativeTrack {
        let existingTrack = database.getTrack(id: track.stableId)
        try database.upsert(track)
        let savedTrack = database.getTrack(id: track.stableId) ?? track
        removeReplacedSandboxFiles(previousTrack: existingTrack, savedTrack: savedTrack)
        return savedTrack
    }

    private func removeReplacedSandboxFiles(previousTrack: NativeTrack?, savedTrack: NativeTrack) {
        guard let previousTrack = previousTrack else { return }
        if let previousPath = previousTrack.localFilePath, previousPath != savedTrack.localFilePath {
            try? FileManager.default.removeItem(atPath: previousPath)
        }
        if let previousArtworkPath = previousTrack.albumArtUri, previousArtworkPath != savedTrack.albumArtUri {
            try? FileManager.default.removeItem(atPath: previousArtworkPath)
        }
    }

    func getLibraryPage(offset: Int, limit: Int, search: String?, sort: String?) -> [String: Any] {
        database.getLibraryPage(offset: offset, limit: limit, search: search, sort: sort).dictionary
    }

    func findTrack(id: String) -> NativeTrack? {
        database.getTrack(id: id)
    }

    func getTrack(id: String) -> [String: Any] {
        guard let track = findTrack(id: id) else {
            return [
                "status": "not_found",
                "track": NSNull(),
            ]
        }
        return [
            "status": "ok",
            "track": track.dictionary,
        ]
    }

    func deleteTrack(id: String) throws -> [String: Any] {
        guard let track = try database.deleteTrack(id: id) else {
            return [
                "status": "not_found",
                "deleted": false,
            ]
        }

        if let localFilePath = track.localFilePath, FileManager.default.fileExists(atPath: localFilePath) {
            try? FileManager.default.removeItem(atPath: localFilePath)
        }

        if let albumArtUri = track.albumArtUri, FileManager.default.fileExists(atPath: albumArtUri) {
            try? FileManager.default.removeItem(atPath: albumArtUri)
        }

        return [
            "status": "ok",
            "deleted": true,
            "track": track.dictionary,
        ]
    }
}
