import Foundation

final class NativeTrackRepository {
    private let database = NativeLibraryDatabase()

    func getLibraryPage(offset: Int, limit: Int, search: String?, sort: String?) -> [String: Any] {
        database.getLibraryPage(offset: offset, limit: limit, search: search, sort: sort)
    }
}
