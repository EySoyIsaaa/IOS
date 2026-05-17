import Foundation

final class NativeQueueManager {
    private(set) var trackIds: [String] = []
    private(set) var currentIndex: Int = 0

    var currentTrackId: String? {
        guard !trackIds.isEmpty, currentIndex >= 0, currentIndex < trackIds.count else {
            return nil
        }
        return trackIds[currentIndex]
    }

    var dictionary: [String: Any] {
        [
            "trackIds": trackIds,
            "currentIndex": currentIndex,
            "currentTrackId": jsonOrNull(currentTrackId),
        ]
    }

    func setQueue(trackIds: [String], startIndex: Int) {
        self.trackIds = trackIds
        guard !trackIds.isEmpty else {
            currentIndex = 0
            return
        }
        currentIndex = min(max(startIndex, 0), trackIds.count - 1)
        print("[NativeQueue] currentIndex=\(currentIndex) currentTrackId=\(currentTrackId ?? "nil")")
    }

    func setCurrentTrackId(_ trackId: String) {
        if let index = trackIds.firstIndex(of: trackId) {
            currentIndex = index
        } else {
            trackIds = [trackId]
            currentIndex = 0
        }
    }

    func setCurrentIndex(_ index: Int) {
        guard !trackIds.isEmpty else {
            currentIndex = 0
            return
        }
        currentIndex = min(max(index, 0), trackIds.count - 1)
        print("[NativeQueue] currentIndex=\(currentIndex) currentTrackId=\(currentTrackId ?? "nil")")
    }

    func moveNext() -> String? {
        guard !trackIds.isEmpty else { return nil }
        guard currentIndex + 1 < trackIds.count else { return nil }
        currentIndex += 1
        return currentTrackId
    }

    func movePrevious() -> String? {
        guard !trackIds.isEmpty else { return nil }
        guard currentIndex > 0 else { return nil }
        currentIndex -= 1
        return currentTrackId
    }
}


private func jsonOrNull<T>(_ value: T?) -> Any {
    guard let value = value else {
        return NSNull()
    }
    return value
}
