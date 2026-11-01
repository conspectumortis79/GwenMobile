import AVFoundation

@MainActor
enum PersonalVoiceAccess {
    static var status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    }

    static func request() async -> AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
