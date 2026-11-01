@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class BubbleCardRenderTests: GwenTestCase {
    private lazy var paths = temporaryPaths("bubble-cards")
    private lazy var media = MediaStore(paths: paths)
    private lazy var documents = DocumentStore(paths: paths)
    private lazy var feed = ImageFeed(reader: media)

    private func render(_ bubble: Bubble) -> UIImage? {
        renderView(staged(bubble), width: 360)
    }

    private func staged(_ bubble: Bubble) -> some View {
        bubble.environmentObject(feed)
            .environmentObject(GallerySelection())
            .environmentObject(GalleryOperation())
    }

    private func bubble(_ message: ChatMessage) -> Bubble {
        Bubble(message: message, media: media, documents: documents, photos: PhotoLibraryWriter())
    }

    private func source(_ index: Int) -> WebSource {
        WebSource(title: "Quelle \(index)", url: "https://q\(index).test/a", domain: "q\(index).test")
    }

    private func review(verified: Bool) -> SourceReview {
        var review = SourceReview()
        review.sourceDomains = 3
        review.sourceGroups = [[1, 2], [3]]
        review.citedSources = 3
        review.citedOrigins = 2
        review.citedClaims = 2
        review.crossChecked = true
        review.checkedClaims = 2
        review.unsupported = ["Eine unbelegte Aussage"]
        review.results = [SourceReview.ClaimResult(claim: "Eine unbelegte Aussage", verdict: .unsupported,
                                                   sources: [2], contradicts: [])]
        review.verified = verified
        return review
    }

    private func file(_ name: String, kind: FileKind = .pdf, chars: Int = 900) -> AttachedFile {
        AttachedFile(file: "doc_\(name)", name: name, kind: kind, bytes: 12_000, pages: 2,
                     chars: chars, truncated: false, via: .ocr)
    }

    private func fullBriefing() -> DayBriefingRef {
        var ref = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                 weather: WeatherFixture.ref(hours: WeatherFixture.day {
                                     WeatherFixture.hour($0, rain: 60, kind: .rain)
                                 }))
        ref.events = [DayBriefingEvent(id: "e1", title: "Zahnarzt", start: Date(),
                                       location: "Praxis", calendar: "Privat")]
        ref.reminders = [DayBriefingItem(id: "r1", title: "Milch", detail: "Einkauf", badge: "2")]
        ref.birthdays = [DayBriefingItem(id: "g1", title: "Anna", detail: "wird 30")]
        ref.travel = DayBriefingTravel(title: "Zahnarzt", carMinutes: 18)
        return ref
    }

    private func weather() -> WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day {
            WeatherFixture.hour($0, temp: 12 + Double($0), rain: 30, kind: .rain)
        })
    }

    private func watch() -> PriceWatchRef {
        PriceWatchRef(watch: PriceWatch(terms: ["PS5", "Slim"], goal: 400, wording: "PS5 Slim",
                                        currencyCode: "EUR", lastCheckedAt: Date(), lastPrice: 379,
                                        lastCurrency: "EUR", lastShop: "MediaMarkt",
                                        lastURL: "https://shop.test/ps5", lastProduct: "PS5 Slim"))
    }

    private func gallery() -> PictureGallery {
        PictureGallery(query: "Eiffelturm",
                       pictures: [WebPicture(file: "web_a.jpg", pageURL: "https://q.test/a",
                                             fullURL: "https://cdn.q.test/a.jpg", title: "Eiffelturm",
                                             domain: "q.test")],
                       shown: 1, exhausted: false)
    }

    func testThePlainStreamingAndUserBubblesDraw() async throws {
        XCTAssertNotNil(render(bubble(ChatMessage(role: .assistant, text: "Antwort [1]"))))
        var streaming = bubble(ChatMessage(role: .assistant, text: "Denkt nach"))
        streaming.streaming = true
        XCTAssertNotNil(render(streaming))
        let user = ChatMessage(role: .user, text: "Frage", images: [Attachment(file: "a.jpg")])
        XCTAssertNotNil(render(bubble(user)))
    }

    func testTheSourcesAndReviewDraw() async throws {
        var message = ChatMessage(role: .assistant, text: "Antwort [1] mit [2]")
        message.sources = [source(1), source(2), source(3)]
        message.sourcesHeadingKey = "research_head"
        message.sourceReview = review(verified: true)
        XCTAssertNotNil(render(bubble(message)))
        message.sourceReview = review(verified: false)
        XCTAssertNotNil(render(bubble(message)))
        var empty = ChatMessage(role: .assistant, text: "ohne Quellen")
        empty.sources = []
        empty.sourceReview = review(verified: false)
        XCTAssertNotNil(render(bubble(empty)))
    }

    func testTheFilesOcrAndFileRefsDraw() {
        var message = ChatMessage(role: .assistant, text: "Dateien")
        message.files = [file("Protokoll.pdf"), file("Notiz.txt", kind: .text)]
        message.ocrFiles = [OcrFile(file: "ocr/scan.jpg", chars: 1_200)]
        message.fileRefs = [FileRef(name: "Anhang.docx", detail: "2 Seiten", via: .docx)]
        message.fileRefsHeadingKey = "file_head"
        XCTAssertNotNil(render(bubble(message)))
    }

    func testTheMemoryAndPlaceCardsDraw() {
        var message = ChatMessage(role: .assistant, text: "Orte")
        message.memoryRefs = [MemoryRef(entry: MemoryEntry(text: "mag Tee", category: .likes,
                                                           source: .manual))]
        message.placeGroups = [PlaceGroup(headingKey: "place_head",
                                          places: [NearbyPlace(name: "Apotheke", latitude: 48.1,
                                                               longitude: 11.5, metres: 350),
                                                   NearbyPlace(name: "Bäckerei", metres: 1_400)])]
        let onRoute: (NearbyPlace) -> Void = { _ in }
        let hosted = Bubble(message: message, media: media, documents: documents,
                            photos: PhotoLibraryWriter(), onRoute: onRoute)
        XCTAssertNotNil(render(hosted))
    }

    func testTheWeatherPriceWatchAndBriefingCardsDraw() async throws {
        var message = ChatMessage(role: .assistant, text: "Karten")
        message.weatherRef = weather()
        message.priceWatchRef = watch()
        message.dayBriefingRef = fullBriefing()
        let controller = mountView(staged(bubble(message)), size: CGSize(width: 360, height: 1200))
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(render(bubble(message)))
    }

    func testTheCalendarReminderScanAndOfferDraw() {
        var message = ChatMessage(role: .assistant, text: "Termine")
        message.calendarRef = CalendarRef(eventID: "ev-1", title: "Zahnarzt", start: Date())
        message.reminderRef = ReminderRef(reminderID: "rem-1", title: "Anrufen", list: "Privat",
                                          due: Date(), allDay: false, place: nil)
        message.scanRef = file("Scan.pdf")
        message.reminderOffer = ScanReminderOffer(title: "Rechnung zahlen", due: Date(),
                                                  allDay: false, list: "Privat", notes: nil)
        let onOffer: (UUID, ScanReminderOffer) -> Void = { _, _ in }
        var hosted = bubble(message)
        hosted.onOpenEvent = { _ in }
        hosted.onReminderOffer = onOffer
        XCTAssertNotNil(render(hosted))
    }

    func testTheGalleryAndPicturesDraw() {
        var message = ChatMessage(role: .assistant, text: "Bilder")
        message.gallery = gallery()
        message.outImages = [Attachment(file: "out_a.jpg")]
        message.images = [Attachment(file: "a.jpg")]
        let onPicture: (WebPicture) -> Void = { _ in }
        var hosted = Bubble(message: message, media: media, documents: documents,
                            photos: PhotoLibraryWriter(), onEdit: { _ in }, onPreview: { _ in })
        hosted.onOpenPicture = onPicture
        hosted.onMorePictures = {}
        XCTAssertNotNil(render(hosted))
    }

    func testTheFooterWithModelThinkingAndActionsDraws() async throws {
        var message = ChatMessage(role: .assistant, text: "Antwort")
        message.model = "qwen3.8-flash"
        message.elapsed = 1.2
        message.thinking = .high
        let hosted = Bubble(message: message, media: media, documents: documents,
                            photos: PhotoLibraryWriter(), time: "12:00", isLast: true,
                            onDelete: { _ in })
        let controller = mountView(staged(hosted), size: CGSize(width: 360, height: 400))
        try await settleHosted(controller)
        XCTAssertNotNil(render(hosted))
    }
}
