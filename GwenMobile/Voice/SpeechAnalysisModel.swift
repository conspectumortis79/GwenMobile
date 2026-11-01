import GwenMobileKit
import AVFoundation
import Foundation
import Speech

struct SpeechPiece: Sendable {
    var text: String
    var isFinal: Bool
}

@MainActor
protocol SpeechAnalysisSessioning: AnyObject {
    func prepare(hints: [String]) async throws -> AVAudioFormat
    func start(input: AsyncStream<AnalyzerInput>) async throws -> AsyncThrowingStream<SpeechPiece, Error>
    func finish() async throws
    func cancel() async
}
