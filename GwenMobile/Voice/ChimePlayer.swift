import GwenMobileKit
import AVFoundation
import Foundation

@MainActor
protocol SoundCueing {
    func play()
}

final class RetainedSoundPlayer: @unchecked Sendable {
    private final class Playing: @unchecked Sendable {
        let player: AVAudioPlayer

        init(_ player: AVAudioPlayer) {
            self.player = player
        }
    }

    private let queue = DispatchQueue(label: "com.mortis.gwenmobile.sound", qos: .userInitiated)
    private var players: [AVAudioPlayer] = []

    func play(label: String, _ make: () throws -> AVAudioPlayer) -> Bool {
        let player: AVAudioPlayer
        do {
            player = try make()
        } catch {
            flowMark("TON \(label) fehler " + TextLine.oneLine(error.localizedDescription, limit: 120))
            return false
        }
        let playing = Playing(player)
        queue.async { [self] in
            players.removeAll { !$0.isPlaying }
            players.append(playing.player)
            playing.player.prepareToPlay()
            let started = playing.player.play()
            flowMark("TON \(label) spielt=\(started)")
        }
        return true
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
