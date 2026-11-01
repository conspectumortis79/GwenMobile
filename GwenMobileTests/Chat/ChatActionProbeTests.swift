@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatActionProbeTests: GwenTestCase {
    @FocusState private var focus: Bool

    private func storedImage(_ media: MediaStore) -> Attachment {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        return Attachment(file: media.storeImageData(image.pngData() ?? Data()) ?? "fehlt.jpg")
    }

    private func fullBubble(_ store: ChatStore, _ media: MediaStore) -> Bubble {
        let att = storedImage(media)
        let ocrName = OcrTextStore.name(imageDate: Date())
        OcrTextCache.shared.remember("Erkannter Text", for: ocrName)
        let reviewed = WebSource(title: "Quelle", url: "tel:0171", domain: "example.com")
        SourceReports.shared.report("example.com")
        var message = ChatMessage(role: .assistant, text: "Antwort mit [1] und [2]")
        message.images = [att]
        message.outImages = [att]
        message.sources = [reviewed, WebSource(title: "Zweite", url: "tel:0172", domain: "zwei.test")]
        message.gallery = PictureGallery(query: "Bilder",
                                         pictures: [WebPicture(file: att.file, pageURL: "tel:0171",
                                                               fullURL: "tel:0172", title: "Bild",
                                                               domain: "example.com")],
                                         shown: 1, exhausted: false)
        message.placeGroups = [PlaceGroup(headingKey: PlaceGroup.defaultHeadingKey,
                                          places: [NearbyPlace(name: "Apotheke", latitude: 48.1,
                                                               longitude: 11.5, metres: 100)])]
        message.calendarRef = CalendarRef(eventID: "e1", title: "Termin", start: Date())
        message.reminderRef = ReminderRef(reminderID: "r1", title: "Milch", list: "Privat",
                                          due: Date(), allDay: false, place: nil)
        message.scanRef = AttachedFile(file: "doc_scan.pdf", name: "Scan.pdf", kind: .pdf,
                                       bytes: 900, pages: 1, chars: 90, via: .ocr)
        message.reminderOffer = ScanReminderOffer(title: "Rechnung zahlen", due: Date())
        message.ocrFiles = [OcrFile(file: ocrName, chars: 14)]
        message.files = [AttachedFile(file: "doc_note.txt", name: "Notiz.txt", kind: .text,
                                      bytes: 10, chars: 6)]
        message.fileRefs = [FileRef(name: "Notiz.txt", detail: "6 Zeichen", via: .plain)]
        message.memoryRefs = [MemoryRef(entry: MemoryEntry(text: "mag Tee", category: .likes))]
        message.model = "qwen"
        message.weatherRef = WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })
        message.dayBriefingRef = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
        message.priceWatchRef = PriceWatchRef(watch: PriceWatch(terms: ["PS5"], goal: 400))
        message.thinking = .low
        var bubble = Bubble(message: message, media: media, documents: store.documents,
                            photos: PhotoLibraryWriter(library: FakePhotoLibrary()), isLast: true)
        bubble.onDelete = { _ in }
        bubble.onRoute = { _ in }
        bubble.onCall = { _ in }
        bubble.onEdit = { _ in }
        bubble.onPreview = { _ in }
        bubble.onOpenPicture = { _ in }
        bubble.onMorePictures = {}
        bubble.onBriefingDay = { _, _ in }
        bubble.onBriefingSpeak = { _ in }
        bubble.onBriefingNotify = { _ in }
        bubble.onWeatherDay = { _, _ in }
        bubble.onWeatherSpeak = { _ in }
        bubble.onReminderOffer = { _, _ in }
        bubble.onOpenEvent = { _ in }
        return bubble
    }

    func testSmokeTheWholeBubbleAndItsMenusDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let (store, media) = stagedStore("chat-probe-bubble")
        let bubble = fullBubble(store, media)
        let controller = mountView(bubble.environmentObject(store.images)
            .environmentObject(GallerySelection())
            .environmentObject(GalleryOperation()), size: CGSize(width: 390, height: 2600))
        try await settleHosted(controller, milliseconds: 400)
        runProbedActions()
        try await settleHosted(controller, milliseconds: 400)
        runProbedActions()
        let menu = mountView(bubble.bubbleContextMenu, size: CGSize(width: 300, height: 200))
        try await settleHosted(menu, milliseconds: 200)
        runProbedActions()
        let sources = mountView(bubble.sourcesView, size: CGSize(width: 390, height: 400))
        try await settleHosted(sources, milliseconds: 200)
        runProbedActions()
        dismissPresentedSheets()
    }

    func testSmokeTheThreadAndHeaderDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let (store, _) = stagedStore("chat-probe-thread")
        let autoScroll = ChatAutoScroll()
        autoScroll.dragChanged(translation: -200)
        autoScroll.follow("anker", using: { _ in })
        let convID = store.current?.id ?? UUID()
        let message = ChatMessage(role: .assistant, text: "Antwort")
        store.appendMessage(message, to: convID)
        let selection = GallerySelection()
        let thread = ChatThreadView(autoScroll: autoScroll, busy: BusyOverlay(),
                                    voice: VoiceTranscriber(), routeDesk: RouteDesk(),
                                    gallerySelection: selection, sourceChecks: [],
                                    isStreaming: false, streamText: "", webStatus: nil,
                                    inputFocused: $focus,
                                    actionsFor: { _ in
            ChatThreadRowActions(onEdit: { _ in }, onPreview: { _, _ in }, onDelete: { _ in },
                                 onRoute: { _ in })
        }, onScrollProxy: { _ in }, onPlaceCall: { _ in }, onDropFiles: { _ in })
            .environmentObject(store)
        let controller = mountView(thread, size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 400)
        runProbedActions()
        try await settleHosted(controller, milliseconds: 400)
        runProbedActions()
        selection.begin(owner: message.id)
        let header = ChatHeaderView(showHistory: .constant(false),
                                    showSettings: .constant(false), onNewChat: {}, onToggleListen: {},
                                    onCancelGallery: {})
            .environmentObject(store)
            .environmentObject(selection)
        let headerHost = mountView(header, size: CGSize(width: 390, height: 160))
        try await settleHosted(headerHost, milliseconds: 300)
        runProbedActions()
        dismissPresentedSheets()
    }

    func testSmokeTheHistoryAndCopyViewsDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let (store, media) = stagedStore("chat-probe-history")
        store.newConversation()
        let cleaner = HistoryCleaner(store: store, media: media, documents: store.documents,
                                     exports: store.exports, feed: store.images)
        let history = HistoryView().environmentObject(store).environmentObject(cleaner)
        let controller = mountView(history, size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 500)
        runProbedActions()
        try await settleHosted(controller, milliseconds: 300)
        runProbedActions()
        let copy = AnswerCopyButton(text: "Antwort")
        let copyHost = mountView(copy, size: CGSize(width: 200, height: 120))
        try await settleHosted(copyHost, milliseconds: 150)
        runProbedActions()
        runProbedActions()
        dismissPresentedSheets()
    }
}
