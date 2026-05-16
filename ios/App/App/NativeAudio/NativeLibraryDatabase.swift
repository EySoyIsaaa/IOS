import Foundation

final class NativeLibraryDatabase {
    func getLibraryPage(offset: Int, limit: Int, search: String?, sort: String?) -> [String: Any] {
        [
            "status": NativeAudioStubStatus.notImplemented.rawValue,
            "tracks": [],
            "offset": offset,
            "limit": limit,
            "total": 0,
        ]
    }
}
