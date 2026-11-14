@testable import GwenMobileFeatureCore
import AVFoundation
import Foundation

extension TapProbe {
    static func drain() -> [() -> Void] {
        let current = actions
        reset()
        return current
    }

    static func reset() {
        actions = []
        indexByKey = [:]
    }
}

extension AudioLevelMeter {
    func measure(_ buffer: AVAudioPCMBuffer, at now: Date = Date()) {
        measure(peak: SpeechLevelBoost.peak(of: buffer), at: now)
    }
}

extension WeatherService {
    static func clearCache() {
        cache.set([:])
    }
}
