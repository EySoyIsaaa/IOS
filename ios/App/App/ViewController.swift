import UIKit
import Capacitor

class ViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        super.capacitorDidLoad()
        registerEpicenterNativePlugin()
    }

    private func registerEpicenterNativePlugin() {
        bridge?.registerPluginInstance(EpicenterNativePlugin())
        NSLog("[iOS Native] EpicenterNativePlugin registered with Capacitor bridge")
    }
}
