import GwenMobileKit
import AVFoundation

@MainActor
protocol SoundCueing {
    func play()
}

@MainActor
final class RetainedSoundPlayer {
    private var player: AVAudioPlayer?

    func play(label: String, _ make: () throws -> AVAudioPlayer) -> Bool {
        do {
            let player = try make()
            player.prepareToPlay()
            let playing = player.play()
            self.player = player
            flowMark("TON \(label) spielt=\(playing)")
            return playing
        } catch {
            flowMark("TON \(label) fehler " + TextLine.oneLine(error.localizedDescription, limit: 120))
            return false
        }
    }
}

@MainActor
final class ChimePlayer: SoundCueing {
    private let name: String
    private let sound: Data
    private let output = RetainedSoundPlayer()

    init(tone: ChimeTone) {
        name = tone.name
        sound = WaveFile.pcm16(tone.samples, sampleRate: ChimeTone.sampleRate)
    }

    nonisolated(unsafe) static var playFailure: Error?

    func play() {
        _ = output.play(label: name) {
            if let playFailure = Self.playFailure { throw playFailure }
            return try AVAudioPlayer(data: sound, fileTypeHint: AVFileType.wav.rawValue)
        }
    }
}
