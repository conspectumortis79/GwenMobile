import GwenMobileKit
import AVFoundation
import Foundation

enum AudioRound {
    static let playback = LockedValue(0)
    static let recording = LockedValue(0)
    static let capturing = LockedValue(0)
}

actor AudioRoute {
    static let shared = AudioRoute()
    nonisolated(unsafe) static var playbackDelay: Duration?

    @discardableResult
    func startPlayback() async -> Int {
        if let playbackDelay = Self.playbackDelay {
            try? await Task.sleep(for: playbackDelay)
        }
        let current = AudioRound.playback.mutate { round in
            round += 1
            return round
        }
        let session = AVAudioSession.sharedInstance()
        guard AudioRound.capturing.current == 0 else {
            try? session.setActive(true)
            return current
        }
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? session.setActive(true)
        return current
    }

    func endPlayback(atRound round: Int) {
        guard ownsRelease(round, counter: AudioRound.playback, category: .playback) else { return }
        deactivate()
    }

    func endRecording(atRound round: Int) {
        guard ownsRelease(round, counter: AudioRound.recording, category: .playAndRecord) else { return }
        resetToDefaultCategory()
        deactivate()
    }

    private func ownsRelease(_ round: Int, counter: LockedValue<Int>,
                             category: AVAudioSession.Category) -> Bool {
        counter.current == round && AVAudioSession.sharedInstance().category == category
    }

    private func resetToDefaultCategory() {
        try? AVAudioSession.sharedInstance().setCategory(.soloAmbient, mode: .default)
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
