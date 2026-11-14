import GwenMobileKit
import AVFoundation

struct RecordingSetup: Equatable, Sendable {
    let label: String
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    static let baseOptions: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
    static let handsFree = RecordingSetup(label: "freisprech", mode: .measurement, options: baseOptions)

    static var preferred: [RecordingSetup] {
        #if !targetEnvironment(macCatalyst)
        return [RecordingSetup(label: "hochwertig", mode: .default,
                               options: baseOptions.union(.bluetoothHighQualityRecording)), handsFree]
        #else
        return [handsFree]
        #endif
    }
}
