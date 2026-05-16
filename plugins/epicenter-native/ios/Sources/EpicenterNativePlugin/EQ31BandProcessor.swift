import Foundation

final class EQ31BandProcessor {
    private(set) var gains: [Double] = Array(repeating: 0, count: 31)

    func setBands(_ gains: [Double]) -> [String: Any] {
        self.gains = Array(gains.prefix(31))
        if self.gains.count < 31 {
            self.gains.append(contentsOf: Array(repeating: 0, count: 31 - self.gains.count))
        }
        return ["status": NativeAudioStubStatus.notImplemented.rawValue, "bands": self.gains]
    }
}
