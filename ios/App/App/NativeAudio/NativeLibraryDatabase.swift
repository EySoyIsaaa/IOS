import Foundation
import SQLite3

final class NativeLibraryDatabase {
    enum DatabaseError: Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message):
                return message
            }
        }
    }

    static let shared = NativeLibraryDatabase()

    private let queue = DispatchQueue(label: "com.epicenter.hifi.native-library-db")
    private let databaseURL: URL
    private var db: OpaquePointer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("NativeLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("tracks.sqlite")
        queue.sync {
            do {
                try openIfNeeded()
                try migrate()
            } catch {
                NSLog("NativeLibraryDatabase initialization failed: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func upsert(_ track: NativeTrack) throws {
        try queue.sync {
            try openIfNeeded()
            let sql = """
            INSERT INTO tracks (
                id, stable_id, title, artist, album, duration_ms, file_name, file_extension,
                source_uri, bookmark_data, local_file_path, source_type, added_at, updated_at,
                size_bytes, sample_rate, bit_depth, bitrate, channel_count, album_art_uri,
                is_available, play_count, last_played_at, codec, quality_class,
                original_url, playback_url, optimized_url, optimized_for_playback, optimization_status,
                optimization_error, original_bit_depth, original_sample_rate, original_bitrate, original_format
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(stable_id) DO UPDATE SET
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_ms = excluded.duration_ms,
                file_name = excluded.file_name,
                file_extension = excluded.file_extension,
                codec = excluded.codec,
                quality_class = excluded.quality_class,
                source_uri = excluded.source_uri,
                bookmark_data = excluded.bookmark_data,
                local_file_path = excluded.local_file_path,
                source_type = excluded.source_type,
                updated_at = excluded.updated_at,
                size_bytes = excluded.size_bytes,
                sample_rate = excluded.sample_rate,
                bit_depth = excluded.bit_depth,
                bitrate = excluded.bitrate,
                channel_count = excluded.channel_count,
                album_art_uri = excluded.album_art_uri,
                is_available = excluded.is_available,
                original_url = excluded.original_url,
                playback_url = excluded.playback_url,
                optimized_url = excluded.optimized_url,
                optimized_for_playback = excluded.optimized_for_playback,
                optimization_status = excluded.optimization_status,
                optimization_error = excluded.optimization_error,
                original_bit_depth = excluded.original_bit_depth,
                original_sample_rate = excluded.original_sample_rate,
                original_bitrate = excluded.original_bitrate,
                original_format = excluded.original_format
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(track, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastErrorMessage())
            }
        }
    }

    func getTrack(id: String) -> NativeTrack? {
        queue.sync {
            do {
                try openIfNeeded()
                let sql = "SELECT * FROM tracks WHERE id = ? OR stable_id = ? LIMIT 1"
                let statement = try prepare(sql)
                defer { sqlite3_finalize(statement) }
                bindText(id, to: statement, at: 1)
                bindText(id, to: statement, at: 2)
                if sqlite3_step(statement) == SQLITE_ROW {
                    return readTrack(from: statement)
                }
            } catch {
                NSLog("NativeLibraryDatabase getTrack failed: \(error.localizedDescription)")
            }
            return nil
        }
    }

    func getLibraryPage(offset: Int, limit: Int, search: String?, sort: String?) -> NativeLibraryPage {
        queue.sync {
            do {
                try openIfNeeded()
                let normalizedOffset = max(offset, 0)
                let normalizedLimit = min(max(limit, 1), 500)
                let searchTerm = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let hasSearch = !searchTerm.isEmpty
                let whereClause = hasSearch ? "WHERE title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\' OR file_name LIKE ? ESCAPE '\\'" : ""
                let orderBy = orderByClause(for: sort)

                let countSql = "SELECT COUNT(*) FROM tracks \(whereClause)"
                let countStatement = try prepare(countSql)
                defer { sqlite3_finalize(countStatement) }
                if hasSearch {
                    bindSearch(searchTerm, to: countStatement)
                }
                var total = 0
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(countStatement, 0))
                }

                let pageSql = "SELECT * FROM tracks \(whereClause) \(orderBy) LIMIT ? OFFSET ?"
                let pageStatement = try prepare(pageSql)
                defer { sqlite3_finalize(pageStatement) }
                var bindIndex: Int32 = 1
                if hasSearch {
                    bindSearch(searchTerm, to: pageStatement)
                    bindIndex = 5
                }
                sqlite3_bind_int(pageStatement, bindIndex, Int32(normalizedLimit))
                sqlite3_bind_int(pageStatement, bindIndex + 1, Int32(normalizedOffset))

                var tracks: [NativeTrack] = []
                while sqlite3_step(pageStatement) == SQLITE_ROW {
                    tracks.append(readTrack(from: pageStatement))
                }

                return NativeLibraryPage(tracks: tracks, offset: normalizedOffset, limit: normalizedLimit, total: total)
            } catch {
                NSLog("NativeLibraryDatabase getLibraryPage failed: \(error.localizedDescription)")
                return NativeLibraryPage(tracks: [], offset: max(offset, 0), limit: min(max(limit, 1), 500), total: 0)
            }
        }
    }

    func deleteTrack(id: String) throws -> NativeTrack? {
        try queue.sync {
            try openIfNeeded()
            guard let track = getTrackUnsafe(id: id) else {
                return nil
            }
            let statement = try prepare("DELETE FROM tracks WHERE id = ? OR stable_id = ?")
            defer { sqlite3_finalize(statement) }
            bindText(id, to: statement, at: 1)
            bindText(id, to: statement, at: 2)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastErrorMessage())
            }
            return track
        }
    }

    private func openIfNeeded() throws {
        guard db == nil else { return }
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw DatabaseError.openFailed(lastErrorMessage())
        }
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS tracks (
            id TEXT PRIMARY KEY,
            stable_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            file_name TEXT NOT NULL,
            file_extension TEXT NOT NULL,
            source_uri TEXT NOT NULL,
            bookmark_data BLOB,
            local_file_path TEXT,
            source_type TEXT NOT NULL DEFAULT 'manual-ios',
            added_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            size_bytes INTEGER NOT NULL DEFAULT 0,
            sample_rate INTEGER,
            bit_depth INTEGER,
            bitrate INTEGER,
            channel_count INTEGER,
            album_art_uri TEXT,
            is_available INTEGER NOT NULL DEFAULT 1,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at TEXT,
            codec TEXT,
            quality_class TEXT,
            original_url TEXT,
            playback_url TEXT,
            optimized_url TEXT,
            optimized_for_playback INTEGER NOT NULL DEFAULT 0,
            optimization_status TEXT NOT NULL DEFAULT 'ready',
            optimization_error TEXT,
            original_bit_depth INTEGER,
            original_sample_rate INTEGER,
            original_bitrate INTEGER,
            original_format TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_tracks_added_at ON tracks(added_at);
        CREATE INDEX IF NOT EXISTS idx_tracks_updated_at ON tracks(updated_at);
        ALTER TABLE tracks ADD COLUMN codec TEXT;
        ALTER TABLE tracks ADD COLUMN quality_class TEXT;
        ALTER TABLE tracks ADD COLUMN original_url TEXT;
        ALTER TABLE tracks ADD COLUMN playback_url TEXT;
        ALTER TABLE tracks ADD COLUMN optimized_url TEXT;
        ALTER TABLE tracks ADD COLUMN optimized_for_playback INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE tracks ADD COLUMN optimization_status TEXT NOT NULL DEFAULT 'ready';
        ALTER TABLE tracks ADD COLUMN optimization_error TEXT;
        ALTER TABLE tracks ADD COLUMN original_bit_depth INTEGER;
        ALTER TABLE tracks ADD COLUMN original_sample_rate INTEGER;
        ALTER TABLE tracks ADD COLUMN original_bitrate INTEGER;
        ALTER TABLE tracks ADD COLUMN original_format TEXT;
        """
        let statements = sql
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for statement in statements {
            if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                let message = lastErrorMessage()
                if !statement.uppercased().hasPrefix("ALTER TABLE") || !message.localizedCaseInsensitiveContains("duplicate column") {
                    throw DatabaseError.stepFailed(message)
                }
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ track: NativeTrack, to statement: OpaquePointer?) {
        bindText(track.id, to: statement, at: 1)
        bindText(track.stableId, to: statement, at: 2)
        bindText(track.title, to: statement, at: 3)
        bindNullableText(track.artist, to: statement, at: 4)
        bindNullableText(track.album, to: statement, at: 5)
        sqlite3_bind_int64(statement, 6, track.durationMs)
        bindText(track.fileName, to: statement, at: 7)
        bindText(track.fileExtension, to: statement, at: 8)
        bindText(track.sourceUri, to: statement, at: 9)
        bindData(track.bookmarkData, to: statement, at: 10)
        bindNullableText(track.localFilePath, to: statement, at: 11)
        bindText(track.sourceType, to: statement, at: 12)
        bindText(NativeTrack.dateFormatter.string(from: track.addedAt), to: statement, at: 13)
        bindText(NativeTrack.dateFormatter.string(from: track.updatedAt), to: statement, at: 14)
        sqlite3_bind_int64(statement, 15, track.sizeBytes)
        bindNullableInt(track.sampleRate, to: statement, at: 16)
        bindNullableInt(track.bitDepth, to: statement, at: 17)
        bindNullableInt(track.bitrate, to: statement, at: 18)
        bindNullableInt(track.channelCount, to: statement, at: 19)
        bindNullableText(track.albumArtUri, to: statement, at: 20)
        sqlite3_bind_int(statement, 21, track.isAvailable ? 1 : 0)
        sqlite3_bind_int(statement, 22, Int32(track.playCount))
        bindNullableText(track.lastPlayedAt.map { NativeTrack.dateFormatter.string(from: $0) }, to: statement, at: 23)
        bindNullableText(track.codec, to: statement, at: 24)
        bindNullableText(track.qualityClass, to: statement, at: 25)
        bindNullableText(track.originalUrl, to: statement, at: 26)
        bindNullableText(track.playbackUrl, to: statement, at: 27)
        bindNullableText(track.optimizedUrl, to: statement, at: 28)
        sqlite3_bind_int(statement, 29, track.optimizedForPlayback ? 1 : 0)
        bindText(track.optimizationStatus, to: statement, at: 30)
        bindNullableText(track.optimizationError, to: statement, at: 31)
        bindNullableInt(track.originalBitDepth, to: statement, at: 32)
        bindNullableInt(track.originalSampleRate, to: statement, at: 33)
        bindNullableInt(track.originalBitrate, to: statement, at: 34)
        bindNullableText(track.originalFormat, to: statement, at: 35)
    }

    private func bindSearch(_ value: String, to statement: OpaquePointer?) {
        let escaped = "%\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        for index in 1...4 {
            bindText(escaped, to: statement, at: Int32(index))
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindNullableText(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: statement, at: index)
    }

    private func bindNullableInt(_ value: Int?, to statement: OpaquePointer?, at index: Int32) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func bindData(_ value: Data?, to statement: OpaquePointer?, at index: Int32) {
        guard let value = value else {
            sqlite3_bind_null(statement, index)
            return
        }
        value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    private func getTrackUnsafe(id: String) -> NativeTrack? {
        do {
            let statement = try prepare("SELECT * FROM tracks WHERE id = ? OR stable_id = ? LIMIT 1")
            defer { sqlite3_finalize(statement) }
            bindText(id, to: statement, at: 1)
            bindText(id, to: statement, at: 2)
            if sqlite3_step(statement) == SQLITE_ROW {
                return readTrack(from: statement)
            }
        } catch {
            NSLog("NativeLibraryDatabase getTrackUnsafe failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func readTrack(from statement: OpaquePointer?) -> NativeTrack {
        NativeTrack(
            id: text(statement, 0) ?? UUID().uuidString,
            stableId: text(statement, 1) ?? "",
            title: text(statement, 2) ?? "Unknown Title",
            artist: text(statement, 3),
            album: text(statement, 4),
            durationMs: sqlite3_column_int64(statement, 5),
            fileName: text(statement, 6) ?? "",
            fileExtension: text(statement, 7) ?? "",
            codec: text(statement, 23),
            qualityClass: text(statement, 24),
            sourceUri: text(statement, 8) ?? "",
            originalUrl: text(statement, 25) ?? text(statement, 8),
            playbackUrl: text(statement, 26) ?? text(statement, 10),
            optimizedUrl: text(statement, 27),
            optimizedForPlayback: sqlite3_column_int(statement, 28) == 1,
            optimizationStatus: text(statement, 29) ?? "ready",
            optimizationError: text(statement, 30),
            originalBitDepth: nullableInt(statement, 31) ?? nullableInt(statement, 16),
            originalSampleRate: nullableInt(statement, 32) ?? nullableInt(statement, 15),
            originalBitrate: nullableInt(statement, 33) ?? nullableInt(statement, 17),
            originalFormat: text(statement, 34) ?? text(statement, 7),
            bookmarkData: data(statement, 9),
            localFilePath: text(statement, 10),
            sourceType: text(statement, 11) ?? NativeTrackSourceType.manualIOS.rawValue,
            addedAt: date(statement, 12) ?? Date(),
            updatedAt: date(statement, 13) ?? Date(),
            sizeBytes: sqlite3_column_int64(statement, 14),
            sampleRate: nullableInt(statement, 15),
            bitDepth: nullableInt(statement, 16),
            bitrate: nullableInt(statement, 17),
            channelCount: nullableInt(statement, 18),
            albumArtUri: text(statement, 19),
            isAvailable: sqlite3_column_int(statement, 20) == 1,
            playCount: Int(sqlite3_column_int(statement, 21)),
            lastPlayedAt: date(statement, 22)
        )
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func data(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func nullableInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
    }

    private func date(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        guard let value = text(statement, index) else { return nil }
        return NativeTrack.dateFormatter.date(from: value)
    }

    private func orderByClause(for sort: String?) -> String {
        switch sort {
        case "title": return "ORDER BY title COLLATE NOCASE ASC, artist COLLATE NOCASE ASC"
        case "artist": return "ORDER BY artist COLLATE NOCASE ASC, title COLLATE NOCASE ASC"
        case "album": return "ORDER BY album COLLATE NOCASE ASC, title COLLATE NOCASE ASC"
        case "duration": return "ORDER BY duration_ms DESC, title COLLATE NOCASE ASC"
        case "updatedAt": return "ORDER BY updated_at DESC"
        case "addedAt": return "ORDER BY added_at DESC"
        default: return "ORDER BY added_at DESC"
        }
    }

    private func lastErrorMessage() -> String {
        guard let db = db, let message = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
