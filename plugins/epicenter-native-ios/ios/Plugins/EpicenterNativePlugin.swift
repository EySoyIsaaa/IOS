import Foundation
import Capacitor

@objc(EpicenterNativePlugin)
public class EpicenterNativePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "EpicenterNativePlugin"
    public let jsName = "EpicenterNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "importTracks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLibraryPage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTrack", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteTrack", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPlaybackState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setQueue", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "next", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "previous", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEpicenterEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEpicenterParams", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEqEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEqBand", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEqBands", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEqPreset", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resetEq", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setReverbEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setReverbAmount", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setConcertHallEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setConcertHallAmount", returnType: CAPPluginReturnPromise),
    ]

    private let repository = NativeTrackRepository()

    public override init() {
        super.init()
    }
    private lazy var importer = NativeTrackImporter(repository: repository)
    private lazy var playbackController = NativePlaybackController(repository: repository)

    public override func load() {
        playbackController.setEventEmitter { [weak self] eventName, data in
            self?.notifyListeners(eventName, data: data)
        }
    }

    @objc func importTracks(_ call: CAPPluginCall) {
        guard let presenter = bridge?.viewController else {
            call.reject("Unable to present the iOS document picker")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.importer.importTracks(from: presenter) { result in
                switch result {
                case .success(let tracks):
                    call.resolve([
                        "status": "ok",
                        "tracks": tracks.map { $0.dictionary },
                    ])
                case .failure(let error):
                    call.reject("Unable to import tracks", nil, error)
                }
            }
        }
    }

    @objc func getLibraryPage(_ call: CAPPluginCall) {
        let offset = call.getInt("offset") ?? 0
        let limit = call.getInt("limit") ?? 50
        let search = call.getString("search")
        let sort = call.getString("sort")
        call.resolve(repository.getLibraryPage(offset: offset, limit: limit, search: search, sort: sort))
    }

    @objc func getTrack(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), !id.isEmpty else {
            call.reject("Track id is required")
            return
        }
        call.resolve(repository.getTrack(id: id))
    }

    @objc func deleteTrack(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), !id.isEmpty else {
            call.reject("Track id is required")
            return
        }
        do {
            call.resolve(try repository.deleteTrack(id: id))
        } catch {
            call.reject("Unable to delete track", nil, error)
        }
    }

    @objc func getPlaybackState(_ call: CAPPluginCall) {
        call.resolve(playbackController.getPlaybackState())
    }

    @objc func play(_ call: CAPPluginCall) {
        call.resolve(playbackController.play(trackId: call.getString("trackId")))
    }

    @objc func pause(_ call: CAPPluginCall) {
        call.resolve(playbackController.pause())
    }

    @objc func seek(_ call: CAPPluginCall) {
        let seconds = call.getDouble("seconds") ?? 0
        call.resolve(playbackController.seek(seconds: seconds))
    }

    @objc func stop(_ call: CAPPluginCall) {
        call.resolve(playbackController.stop())
    }

    @objc func setQueue(_ call: CAPPluginCall) {
        let trackIds = call.getArray("trackIds", String.self) ?? []
        let startIndex = call.getInt("startIndex") ?? 0
        call.resolve(playbackController.setQueue(trackIds: trackIds, startIndex: startIndex))
    }

    @objc func next(_ call: CAPPluginCall) {
        call.resolve(playbackController.next())
    }

    @objc func previous(_ call: CAPPluginCall) {
        call.resolve(playbackController.previous())
    }

    @objc func setEpicenterEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve(playbackController.setEpicenterEnabled(enabled))
    }

    @objc func setEpicenterParams(_ call: CAPPluginCall) {
        call.resolve(playbackController.setEpicenterParams(
            intensity: call.getDouble("intensity"),
            sweepFreq: call.getDouble("sweepFreq") ?? call.getDouble("sweep"),
            width: call.getDouble("width"),
            balance: call.getDouble("balance"),
            volume: call.getDouble("volume") ?? call.getDouble("output")
        ))
    }

    @objc func setEqEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve(playbackController.setEqEnabled(enabled))
    }

    @objc func setEqBand(_ call: CAPPluginCall) {
        let index = call.getInt("index") ?? -1
        let gain = call.getDouble("gain") ?? 0
        call.resolve(playbackController.setEqBand(index: index, gain: gain))
    }

    @objc func setEqBands(_ call: CAPPluginCall) {
        let gains = call.getArray("gains", Double.self) ?? []
        call.resolve(playbackController.setEqBands(gains))
    }

    @objc func setEqPreset(_ call: CAPPluginCall) {
        let name = call.getString("name")
        let gains = call.getArray("gains", Double.self) ?? []
        call.resolve(playbackController.setEqPreset(name: name, gains: gains))
    }

    @objc func resetEq(_ call: CAPPluginCall) {
        call.resolve(playbackController.resetEq())
    }

    @objc func setReverbEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve(playbackController.setReverbEnabled(enabled))
    }

    @objc func setReverbAmount(_ call: CAPPluginCall) {
        let amount = call.getDouble("amount") ?? 0
        call.resolve(playbackController.setReverbAmount(amount))
    }

    @objc func setConcertHallEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve(playbackController.setConcertHallEnabled(enabled))
    }

    @objc func setConcertHallAmount(_ call: CAPPluginCall) {
        let amount = call.getDouble("amount") ?? 0
        call.resolve(playbackController.setConcertHallAmount(amount))
    }
}
