@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var briefingOpens = BriefingOpenRequests.shared
    @ObservedObject var helpOpens = HelpRequests.shared
    var listenToken: Binding<Int>? = nil
    #if DEBUG
    var testToken: Binding<Int>? = nil
    var testCmd: String = ""
    #endif
    @State var attachMenu = false
    @State var input: String = ""
    @State var pendingItems: [PhotosPickerItem] = []
    @State var pendingImages: [PendingPicture] = []
    @State var pendingFiles: [PendingFile] = []
    @State var dropRunning = false
    @State var isStreaming = false
    @State var isBusy = false
    @State var speechInterrupted = false
    @State var voiceCancelFeedback = false
    @State var streamText: String = ""
    @State var alerts: [L.FriendlyError] = []
    @State var showSettings = false
    @State var settingsCategory: SettingsCategory?
    @State var showHelp = false
    @State var pendingHelpAfterSettings = false
    @State var pendingSettingsAfterHelp = false
    @State var showHistory = false
    @State var showBriefingOpen = false
    @State var briefingOpenDay = BriefingDay.today
    @State var imagePreview: ImagePreviewTarget?
    @State var calendarEvent: CalendarRef?
    @State var webStatus: String? = nil
    @State var streamLease = StreamLease()
    @State var statusLedger = StatusLedger()
    @State var sourceChecks: Set<UUID> = []
    @StateObject var gallerySelection = GallerySelection()
    @StateObject var galleryOperation = GalleryOperation()
    @FocusState var inputFocused: Bool
    @StateObject var busy = BusyOverlay()
    @StateObject var chainRun = ChainRun()
    @StateObject var autoScroll = ChatAutoScroll()
    @StateObject var listenNotice = NoticeLine(lifetime: .milliseconds(1500))
    @State var pendingSuggestions: [MemorySuggestion] = []

    #if DEBUG
    @State var scrollProxy: ScrollViewProxy?
    @State var testRunning = false
    @State var probeLastPlan: SendPlan?
    #endif
    @StateObject var voice = ChatView.defaultVoiceFactory()
    @ObservedObject var microphone = HeldMicrophone.shared
    let listenNotices: any ListenNotifying = LocalListenNotifier()

    @MainActor static var defaultVoiceFactory: () -> VoiceTranscriber = { makeDefaultVoice() }

    @MainActor static func makeDefaultVoice() -> VoiceTranscriber {
        let gate = SpeakerGate()
        return VoiceTranscriber(
            makeSource: {
                let feed = SpeakerAwareFeed(base: HeldMicrophone.shared, gate: gate)
                return VoiceSourcePort.preferred({ feed })
            },
            sentCue: ChosenCue(chosen: { AppSettings.shared.voice.sentSound },
                               chime: ChimePlayer(tone: .sent)),
            speakerGate: gate)
    }
    @StateObject var placeSearch = LivePlaceSearch()
    let productScanner: any ProductScanning = VisionProductScanner()
    @StateObject var priceRegions = LivePriceRegionReading()
    @StateObject var routeDesk = RouteDesk()
    @StateObject var callDesk = CallDesk()
    @State var callPlacing = false
    @StateObject var musicDesk = MusicDesk()
    @StateObject var messageDesk = MessageDesk()
    @StateObject var reminderDesk = ReminderDesk()
    @StateObject var timerDesk = TimerDesk()
    @StateObject var priceWatchDesk = PriceWatchDesk()
    @StateObject var briefingDesk = DayBriefingDesk()
    @State var priceWatchCatchUpRunning = false
    @State var memoryDueRunning = false
    @State var runTask: Task<Void, Never>?
    @State var runGeneration = 0
    var weatherService = WeatherService()
    var chatRunner: @MainActor (URLRequest, @escaping @MainActor (String) -> Void) async throws -> String = {
        request, onChunk in
        try await ChatRunner.shared.run(request, onChunk: onChunk)
    }
    let scanWorkflow = ScanWorkflow()
    @State var handledListen = 0
    @State var handledBriefingOpen = 0
    @State var handledHelp = HelpRequests.shared.token
    @StateObject var speech = SpeechSynthesizer()
    @StateObject var wakeSpeech = SpeechSynthesizer()

    var body: some View {
        #if DEBUG
        let _ = RenderStats.chatBody.bump()
        #endif
        scaffold
    }

    var currentAlert: L.FriendlyError? { alerts.first }

    var alertText: String {
        guard let alert = currentAlert else { return "" }
        return alert.detail.isEmpty ? alert.message : "\(alert.message)\n\n\(alert.detail)"
    }

    func queueAlert(_ alert: L.FriendlyError) {
        guard !alerts.contains(alert) else { return }
        alerts.append(alert)
    }

    func dismissAlert() {
        guard !alerts.isEmpty else { return }
        alerts.removeFirst()
    }

    func syncPendingAlerts() {
        if let error = voice.lastError {
            let wasListening = voice.lastSessionListened
            if wasListening { settings.voice.listenMode = false }
            if settings.voice.conversationMode {
                settings.voice.conversationMode = false
                Task { try? await microphone.setVoiceProcessing(false) }
            }
            if wasListening {
                Task { try? await microphone.setVoiceProcessing(false) }
            }
            queueAlert(error)
            voice.lastError = nil
            syncListenPresence()
        }
        if let problem = store.storageProblem {
            queueAlert(L.FriendlyError(message: problem, detail: "", openSettings: false))
            store.dismissStorageProblem()
        }
    }

    static func timeString(_ date: Date) -> String { Formatters.time(date) }

    static func question(for message: ChatMessage, in messages: [ChatMessage]) -> String? {
        guard message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        return messages.prefix(index).last(where: { $0.role == .user })?.text.nilIfEmpty
    }

    nonisolated static func messageAfterReturn(_ typed: String) -> String? {
        guard typed.last == "\n" else { return nil }
        let message = String(typed.dropLast()).trimmed
        return message.isEmpty ? nil : message
    }
}
