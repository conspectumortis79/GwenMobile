@testable import GwenMobileFeatureCore
import AVFoundation

public enum DeviceSystems {
    @MainActor public static func install() {
        TimerSetterPort.current = SystemTimerSetter()
        RouterStepsPort.current = SystemRouterSteps()
        MediaLibrarySystem.install()
        DialerPort.cellular = { CellularDialerFactory.make() }
        MusicSystem.install()
        PriceRegionSystem.install()
        ShareSystem.install()
        PhotoPickerSystem.install()
        BriefingSystem.install()
        WeatherSystem.install()
        ReminderSystem.install()
        ReminderStoreSystem.install()
        DocumentScannerSystemInstall.install()
        PriceWatchBackgroundPort.current = PriceWatchBackgroundSystem.shared
        TranslationSystem.install()
        MessageSenderPort.carrier = { CarrierMessageSenderFactory.make() }
        MessageSenderPort.compose = { ComposeMessageSender() }
        VoiceSourcePort.preferred = { feed in LiveTranscription.preferred(feed: feed) }
        VoiceHardwarePort.makeTap = { MicrophoneTap() }
        VoiceHardwarePort.makeDisruptions = { AudioDisruptionWatcher() }
        VoiceHardwarePort.makeHeadsets = { HeadsetHandover() }
        VoiceMicrophonePort.allowed = { AVAudioApplication.shared.recordPermission == .granted }
        VoiceMicrophonePort.request = { completion in
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        }
    }
}
