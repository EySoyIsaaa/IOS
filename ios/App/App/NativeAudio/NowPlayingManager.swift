import Foundation
import MediaPlayer
import UIKit

final class NowPlayingManager {
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private var nowPlayingInfo: [String: Any] = [:]
    private var lastElapsedUpdateAt: Date?
    private let minimumElapsedUpdateInterval: TimeInterval = 1.0

    func updateMetadata(for track: NativeTrack, duration: Double, elapsedTime: Double, playbackRate: Double) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(elapsedTime, 0),
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
        ]

        if let artist = track.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = track.album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artwork = makeArtwork(from: track.albumArtUri) {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        nowPlayingInfo = info
        publish(force: true)
    }

    func updatePlayback(elapsedTime: Double, playbackRate: Double, force: Bool = false) {
        guard !nowPlayingInfo.isEmpty else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(elapsedTime, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        publish(force: force)
    }

    func updateStopped(elapsedTime: Double = 0) {
        guard !nowPlayingInfo.isEmpty else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(elapsedTime, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0
        publish(force: true)
    }

    func clear() {
        nowPlayingInfo = [:]
        lastElapsedUpdateAt = nil
        infoCenter.nowPlayingInfo = nil
    }

    private func publish(force: Bool) {
        let now = Date()
        if !force,
           let lastElapsedUpdateAt = lastElapsedUpdateAt,
           now.timeIntervalSince(lastElapsedUpdateAt) < minimumElapsedUpdateInterval {
            return
        }
        lastElapsedUpdateAt = now
        infoCenter.nowPlayingInfo = nowPlayingInfo
    }

    private func makeArtwork(from albumArtUri: String?) -> MPMediaItemArtwork? {
        guard let albumArtUri = albumArtUri, !albumArtUri.isEmpty else { return nil }
        let url: URL
        if albumArtUri.hasPrefix("file://"), let fileURL = URL(string: albumArtUri) {
            url = fileURL
        } else {
            url = URL(fileURLWithPath: albumArtUri)
        }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
