import GwenMobileKit
import AVFoundation
import Foundation
import Speech

struct HeardSegment: Sendable {
    let text: String?
    let final: Bool
    let failure: String?
    let silent: Bool
}

final class RequestSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    var current: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func set(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = next
        lock.unlock()
    }

    static func delivery(_ slot: RequestSlot) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in slot.current?.append(buffer) }
    }
}
