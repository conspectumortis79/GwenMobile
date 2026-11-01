@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Contacts
import EventKit
import MediaPlayer
import Speech
import Translation
import UIKit
import XCTest
import GwenMobileKit

#if !targetEnvironment(macCatalyst)
private enum MediaLibraryDefaults {
    static let playlists = MediaLibraryIndex.playlists
    static let artists = MediaLibraryIndex.artists
    static let albums = MediaLibraryIndex.albums
    static let songs = MediaLibraryIndex.songs
}
#endif

@MainActor
private enum SeamDefaults {
    static let contactStatus = LiveContactDirectory.authorizationStatus
    static let contactRequest = LiveContactDirectory.requestAccess
    static let photoAuthorization = SystemPhotoLibrary.authorization
    static let photoChanges = SystemPhotoLibrary.performChanges
    static let mapOpener = NearbyPlace.mapItemOpener
    static let placeSearch = LivePlaceSearch.searchRunner
    static let briefingGeocode = LiveBriefingTravel.geocode
    static let briefingTravel = LiveBriefingTravel.travelMinutes
    #if !targetEnvironment(macCatalyst)
    static let mediaStatus = MediaLibraryReader.authorizationStatus
    static let mediaRequest = MediaLibraryReader.requestAuthorization
    #endif
    static let reduceMotion = ProcessingDots.reduceMotionOverride
    static let cameraAvailable = CameraPresenter.isCameraAvailable
    static let voiceAllowed = VoiceMicrophonePort.allowed
    static let voiceRequest = VoiceMicrophonePort.request
    static let voiceSource = VoiceSourcePort.preferred
    static let messageCarrier = MessageSenderPort.carrier
    static let messageCompose = MessageSenderPort.compose
    static let photoPicker = PhotoPickerPort.makeItem
    static let musicApp = MusicAppPort.current
    static let countryGeocoder = CountryGeocoderPort.current
    static let reminderPlace = ReminderPlacePort.current
    static let weatherGeocode = WeatherService.defaultGeocode
    static let weatherLocalSearch = WeatherService.defaultLocalSearch
    static let weatherReverse = WeatherService.defaultReverseGeocode
    static let weatherForecastURL = WeatherService.forecastURL
    static let onDeviceCodes = OnDeviceTranslation.liveSupportedCodes
    static let onDeviceStatus = OnDeviceTranslation.liveStatus
    static let onDeviceBatch = OnDeviceTranslation.batch
    static let voiceTap = VoiceHardwarePort.makeTap
    static let voiceDisruptions = VoiceHardwarePort.makeDisruptions
    static let voiceHeadsets = VoiceHardwarePort.makeHeadsets
}

private struct AppSettingsSnapshot: @unchecked Sendable {
    let provider: ProviderID
    let connections: ProviderConnections
    let profiles: [ProviderID: ProviderProfile]
    let voice: VoiceSettings
    let memory: MemorySettings
    let briefing: BriefingSettings
    let music: MusicSettings
    let research: ResearchSettings
    let language: AppLanguage
    let appearance: AppAppearance
    let autoOCR: Bool
    let keys: [ProviderID: String]
    let keysReliable: Bool

    @MainActor init(_ settings: AppSettings) {
        provider = settings.provider
        connections = settings.connections
        profiles = settings.profiles
        voice = settings.voice
        memory = settings.memory
        briefing = settings.briefing
        music = settings.music
        research = settings.research
        language = settings.language
        appearance = settings.appearance
        autoOCR = settings.autoOCR
        keys = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, settings.key(for: $0)) })
        keysReliable = !settings.vault.hasBlockedEntry
    }

    @MainActor func restore(to settings: AppSettings) {
        if settings.provider != provider { settings.provider = provider }
        if settings.connections != connections { settings.connections = connections }
        if settings.profiles != profiles { settings.profiles = profiles }
        if settings.language != language { settings.language = language }
        if settings.appearance != appearance { settings.appearance = appearance }
        if settings.autoOCR != autoOCR { settings.autoOCR = autoOCR }
        if settings.voice != voice { settings.voice = voice }
        if settings.memory != memory { settings.memory = memory }
        if settings.briefing != briefing { settings.briefing = briefing }
        if settings.music != music { settings.music = music }
        if settings.research != research { settings.research = research }
        guard keysReliable else { return }
        var changed = false
        for provider in ProviderID.allCases {
            let wanted = keys[provider] ?? ""
            guard settings.key(for: provider) != wanted else { continue }
            if wanted.isEmpty {
                settings.clearKey(for: provider)
            } else {
                settings.setKey(wanted, for: provider)
            }
            changed = true
        }
        if changed { AppSettings.flushKeySave() }
    }
}

class GwenTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.en)
        MainActor.assumeIsolated { GwenTestCase.restoreVisibleWindow() }
        addTeardownBlock {
            MainActor.assumeIsolated { GwenTestCase.restoreVisibleWindow() }
        }
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(false)
            TapProbe.reset()
            TimerSetterPort.current = StubTimerSetter()
            MessageSenderPort.carrier = SeamDefaults.messageCarrier
            MessageSenderPort.compose = SeamDefaults.messageCompose
            BriefingTravelPort.current = StubBriefingTravel()
            RouterStepsPort.current = SystemRouterSteps()
            PhotoPickerPort.makeItem = SeamDefaults.photoPicker
            CountryGeocoderPort.current = SeamDefaults.countryGeocoder
            MusicAppPort.current = SeamDefaults.musicApp
            DialerPort.cellular = { nil }
            ReminderPlacePort.current = SeamDefaults.reminderPlace
            EventKitReminderStore.liveStore = nil
            WeatherService.defaultGeocode = SeamDefaults.weatherGeocode
            WeatherService.defaultLocalSearch = SeamDefaults.weatherLocalSearch
            WeatherService.defaultReverseGeocode = SeamDefaults.weatherReverse
            WeatherService.forecastURL = SeamDefaults.weatherForecastURL
            DocumentScannerPort.current = StubDocumentScanner()
            PriceWatchBackgroundPort.current = StubPriceWatchBackground()
            OnDeviceTranslation.liveSupportedCodes = SeamDefaults.onDeviceCodes
            OnDeviceTranslation.liveStatus = SeamDefaults.onDeviceStatus
            OnDeviceTranslation.batch = SeamDefaults.onDeviceBatch
            VoiceSourcePort.preferred = SeamDefaults.voiceSource
            VoiceHardwarePort.makeTap = SeamDefaults.voiceTap
            VoiceHardwarePort.makeDisruptions = SeamDefaults.voiceDisruptions
            VoiceHardwarePort.makeHeadsets = SeamDefaults.voiceHeadsets
            VoiceMicrophonePort.allowed = SeamDefaults.voiceAllowed
            VoiceMicrophonePort.request = SeamDefaults.voiceRequest
            QwenAPI.streamIdleOverride = nil
            TranslationFlow.runOverride = nil
            Presenter.hostOverride = nil
            DocumentScanner.shared.isSupportedOverride = nil
            DocumentScannerSystem.isSupportedOverride = nil
            DocumentScanner.shared.scanOverride = nil
            CameraPresenter.shared.isAvailableOverride = nil
            CameraPresenter.shared.captureOverride = nil
            CameraPresenter.isCameraAvailable = SeamDefaults.cameraAvailable
            CameraPresenter.presentCameraOverride = nil
            ChatView.defaultVoiceFactory = { ChatView.makeDefaultVoice() }
            SystemSpeechRecognizer.authorizationStatusOverride = nil
            SystemSpeechRecognizer.requestAuthorization = {
                await SystemSpeechRecognizer.requestAuthorizationLive()
            }
            EventKitReminderStore.storeOverride = nil
            EventKitReminderStore.accessStatusOverride = nil
            SystemPhotoLibrary.authorization = SeamDefaults.photoAuthorization
            SystemPhotoLibrary.performChanges = SeamDefaults.photoChanges
            NearbyPlace.mapItemOpener = SeamDefaults.mapOpener
            LivePlaceSearch.searchRunner = SeamDefaults.placeSearch
            LiveBriefingTravel.geocode = SeamDefaults.briefingGeocode
            LiveBriefingTravel.travelMinutes = SeamDefaults.briefingTravel
            LiveContactDirectory.authorizationStatus = SeamDefaults.contactStatus
            LiveContactDirectory.requestAccess = SeamDefaults.contactRequest
            AssertionShieldActions.raise = { failure in NSException(assertion: failure).raise() }
            ChimePlayer.playFailure = nil
            ProcessingDots.reduceMotionOverride = SeamDefaults.reduceMotion
            #if !targetEnvironment(macCatalyst)
            MediaLibraryReader.authorizationStatus = SeamDefaults.mediaStatus
            MediaLibraryReader.requestAuthorization = SeamDefaults.mediaRequest
            MediaLibraryIndex.playlists = MediaLibraryDefaults.playlists
            MediaLibraryIndex.artists = MediaLibraryDefaults.artists
            MediaLibraryIndex.albums = MediaLibraryDefaults.albums
            MediaLibraryIndex.songs = MediaLibraryDefaults.songs
            #endif
            CalendarService.storeOverride = nil
            CalendarService.accessStatusOverride = nil
            CalendarService.eventsOverride = nil
            AnalyzerSpeechSource.assetStatus = { transcriber in
                await AssetInventory.status(forModules: [transcriber])
            }
            AnalyzerSpeechSource.installationRequest = { transcriber in
                try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])
            }
            OnDeviceTranslation.statusOverride = nil
        }
        MainActor.assumeIsolated {
            AppSettings.shared.voice.conversationMode = false
            AppSettings.shared.voice.listenMode = false
        }
        let snapshot = MainActor.assumeIsolated { AppSettingsSnapshot(AppSettings.shared) }
        addTeardownBlock { [snapshot] in
            MainActor.assumeIsolated { snapshot.restore(to: AppSettings.shared) }
        }
    }

    @MainActor
    private static func restoreVisibleWindow() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let visible = scene.windows.first(where: { !$0.isHidden && $0.rootViewController != nil }) else {
            return
        }
        if !visible.isKeyWindow { visible.makeKeyAndVisible() }
    }

    @MainActor
    func stagedStore(_ prefix: String) -> (store: ChatStore, media: MediaStore) {
        let paths = temporaryPaths(prefix)
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let store = ChatStore(media: media, paths: paths)
        store.newConversation()
        return (store, media)
    }

    @MainActor
    func stagedStoreWithCleaner(_ prefix: String) -> (store: ChatStore, cleaner: HistoryCleaner) {
        let paths = temporaryPaths(prefix)
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        let cleaner = HistoryCleaner(store: store, media: media,
                                     documents: DocumentStore(paths: paths),
                                     exports: ExportStore(paths: paths),
                                     feed: store.images)
        return (store, cleaner)
    }

    @MainActor
    func fakeCalendar(_ title: String = "Privat") -> (fake: FakeCalendarEventStore, calendar: EKCalendar) {
        let fake = FakeCalendarEventStore()
        CalendarService.storeOverride = fake
        CalendarService.accessStatusOverride = .fullAccess
        let calendar = EKCalendar(for: .event, eventStore: fake.eventStore)
        calendar.title = title
        fake.calendarsList = [calendar]
        fake.defaultCalendar = calendar
        return (fake, calendar)
    }

    func temporaryPaths(_ prefix: String) -> StoragePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-" + UUID().uuidString)
        return StoragePaths(documents: root.appendingPathComponent("Documents"),
                            support: root.appendingPathComponent("Support"))
    }

    func makeSupportUnwritable(_ paths: StoragePaths) throws {
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: paths.support.path)
    }

    func restoreSupport(_ paths: StoragePaths) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: paths.support.path)
    }
}

extension XCTestCase {
    func toolFunction(_ name: String, attachable: Bool = false) throws -> [String: Any] {
        let tool = try XCTUnwrap(ToolRouter.tools(attachable: attachable).first {
            ($0["function"] as? [String: Any])?["name"] as? String == name
        })
        return try XCTUnwrap(tool["function"] as? [String: Any])
    }

    func toolProperties(_ name: String, attachable: Bool = false) throws -> [String: Any] {
        let function = try toolFunction(name, attachable: attachable)
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        return try XCTUnwrap(parameters["properties"] as? [String: Any])
    }

    func toolParameters(_ name: String, attachable: Bool = false) throws -> [String: Any] {
        let function = try toolFunction(name, attachable: attachable)
        return try XCTUnwrap(function["parameters"] as? [String: Any])
    }

    func toolDescription(_ name: String, attachable: Bool = false) throws -> String {
        let function = try toolFunction(name, attachable: attachable)
        return try XCTUnwrap(function["description"] as? String)
    }
}
