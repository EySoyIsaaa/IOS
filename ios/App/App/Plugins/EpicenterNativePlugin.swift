import Foundation
import Capacitor

@objc(EpicenterNativePlugin)
public class EpicenterNativePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "EpicenterNativePlugin"
    public let jsName = "EpicenterNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "importTracks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLibraryPage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPlaybackState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEpicenterEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEqBands", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setReverbEnabled", returnType: CAPPluginReturnPromise),
    ]

    private let importer = NativeTrackImporter()
    private let repository = NativeTrackRepository()
    private let playbackController = NativePlaybackController()
    private let eqProcessor = EQ31BandProcessor()
    private let reverbProcessor = ReverbProcessor()

    @objc func importTracks(_ call: CAPPluginCall) {
        call.resolve(importer.importTracks())
    }

    @objc func getLibraryPage(_ call: CAPPluginCall) {
        let offset = call.getInt("offset") ?? 0
        let limit = call.getInt("limit") ?? 50
        let search = call.getString("search")
        let sort = call.getString("sort")
        call.resolve(repository.getLibraryPage(offset: offset, limit: limit, search: search, sort: sort))
    }

    @objc func getPlaybackState(_ call: CAPPluginCall) {
        call.resolve(playbackController.getPlaybackState())
    }

    @objc func play(_ call: CAPPluginCall) {
        call.resolve(playbackController.notImplementedResponse("play"))
    }

    @objc func pause(_ call: CAPPluginCall) {
        call.resolve(playbackController.notImplementedResponse("pause"))
    }

    @objc func seek(_ call: CAPPluginCall) {
        let seconds = call.getDouble("seconds") ?? 0
        var response = playbackController.notImplementedResponse("seek")
        response["seconds"] = seconds
        call.resolve(response)
    }

    @objc func setEpicenterEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve([
            "status": NativeAudioStubStatus.notImplemented.rawValue,
            "method": "setEpicenterEnabled",
            "enabled": enabled,
        ])
    }

    @objc func setEqBands(_ call: CAPPluginCall) {
        let gains = call.getArray("gains", Double.self) ?? []
        call.resolve(eqProcessor.setBands(gains))
    }

    @objc func setReverbEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        call.resolve(reverbProcessor.setEnabled(enabled))
    }
}
