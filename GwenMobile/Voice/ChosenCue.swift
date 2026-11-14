import GwenMobileKit
import AVFoundation

@MainActor
protocol SoundFilePlaying {
    func play(path: String) -> Bool
}

@MainActor
final class SoundFilePlayer: SoundFilePlaying {
    private let output = RetainedSoundPlayer()

    func play(path: String) -> Bool {
        output.play(label: "datei=\(SystemSoundCatalog.name(ofPath: path))") {
            try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        }
    }
}

@MainActor
final class ChosenCue: SoundCueing {
    private let chosen: @MainActor () -> String
    private let chime: any SoundCueing
    private let files: any SoundFilePlaying

    init(chosen: @escaping @MainActor () -> String, chime: any SoundCueing,
         files: any SoundFilePlaying = SoundFilePlayer()) {
        self.chosen = chosen
        self.chime = chime
        self.files = files
    }

    func play() {
        let path = chosen().trimmed
        if !path.isEmpty, files.play(path: path) { return }
        chime.play()
    }
}
