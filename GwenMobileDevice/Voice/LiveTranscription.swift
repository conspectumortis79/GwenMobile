@testable import GwenMobileFeatureCore
import Foundation

@MainActor
enum LiveTranscription {
    static func preferred(feed: @escaping @MainActor () -> any AudioFeeding = { MicrophoneTap() })
        -> any LiveTranscribing {
        PreferredSpeechSource(candidates: [{ AnalyzerSpeechSource(feed: feed()) },
                                           { BufferSpeechSource(feed: feed()) }])
    }
}
