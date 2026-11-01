@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatBubbleGapTests: GwenTestCase {
    private lazy var paths = temporaryPaths("bubble-gap")
    private lazy var media = MediaStore(paths: paths)
    private lazy var documents = DocumentStore(paths: paths)
    private var window: UIWindow?
    private var previousKey: UIWindow?

    private func makeHost() {
        documents.prepareDirectories()
        media.prepareDirectories()
        previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        window = hostWindow(Text("Gastgeber"))
    }

    private func closeHost() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        previousKey?.makeKeyAndVisible()
        previousKey = nil
    }

    private func makeBubble(text: String = "Antwort", user: Bool = false,
                            files: [AttachedFile] = [], ocr: [OcrFile] = [],
                            fileRefs: [FileRef] = [], sources: [WebSource] = []) -> Bubble {
        var message = ChatMessage(role: user ? .user : .assistant, text: text)
        message.files = files
        message.ocrFiles = ocr
        message.fileRefs = fileRefs
        message.sources = sources
        return Bubble(message: message, media: media, documents: documents,
                      photos: PhotoLibraryWriter(library: FakePhotoLibrary()))
    }

    private func storedTextFile(_ name: String = "Notiz.txt") throws -> StoredDocument {
        documents.prepareDirectories()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("Inhalt".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(documents.store(url: url))
    }

    private func storedAttachment() throws -> Attachment {
        media.prepareDirectories()
        let data = try XCTUnwrap(FakePicture.make().pngData())
        return Attachment(file: try XCTUnwrap(media.storeImageData(data)))
    }

    func testSmokeSharingFailuresAreHandled() throws {
        let original = Presenter.shareOverride
        defer { Presenter.shareOverride = original }
        Presenter.shareOverride = { _, _ in throw PresenterError.noHost }
        let answer = makeBubble()
        answer.saveAsFile()
        let stored = try storedTextFile()
        answer.shareStored(stored.url)
        let file = OcrTextStore.name(imageDate: Date())
        OcrTextCache.shared.remember("Text", for: file)
        answer.openOCRFile(OcrFile(file: file, chars: 4))
    }

    func testSmokeSavingTheAnswerAsAFileAndSharingStoredFiles() throws {
        makeHost()
        defer { closeHost() }
        let answer = makeBubble(text: "Antwort zum Sichern")
        answer.saveAsFile()
        let stored = try storedTextFile()
        let file = AttachedFile(file: stored.file, name: "Notiz.txt", kind: .text,
                                bytes: stored.bytes, chars: 6)
        let withFile = makeBubble(files: [file])
        withFile.shareScan(file)
        withFile.shareStored(stored.url)
        withFile.shareStored(nil)
        withFile.openFile(file)
        let missing = makeBubble(files: [AttachedFile(file: "doc_weg.txt", name: "weg.txt",
                                                      kind: .text, bytes: 1, chars: 1)])
        missing.shareScan(file)
        missing.openFile(file)
        dismissPresentedSheets()
    }

    func testTheOCRFileCardsOpenAndShare() async throws {
        let file = OcrTextStore.name(imageDate: Date())
        OcrTextCache.shared.remember("Erkannter Text", for: file)
        let entry = OcrFile(file: file, chars: 14)
        let answer = makeBubble(ocr: [entry])
        XCTAssertEqual(answer.liveOCRFiles.count, 1)
        let controller = mountView(answer.ocrFilesView, size: CGSize(width: 390, height: 200))
        try await settleHosted(controller, milliseconds: 100)
        answer.openOCRFile(entry)
        let unknown = makeBubble(ocr: [OcrFile(file: "ocr/fehlt.jpg", chars: 3)])
        XCTAssertTrue(unknown.liveOCRFiles.isEmpty)
        unknown.openOCRFile(OcrFile(file: "ocr/fehlt.jpg", chars: 3))
    }

    func testSmokeSavingPicturesToTheLibrary() async throws {
        let att = try storedAttachment()
        let answer = makeBubble()
        answer.saveAttachment(att)
        answer.saveAllAttachments()
        answer.saveAll([])
        answer.saveAll([Attachment(file: "gibt_es_nicht.jpg")])
        let denied = FakePhotoLibrary()
        denied.refuseAccess()
        let refusing = Bubble(message: ChatMessage(role: .assistant, text: "x"), media: media,
                              documents: documents, photos: PhotoLibraryWriter(library: denied))
        refusing.saveAll([att])
        try await settle(600)
    }

    func testTheFileViewsDraw() async throws {
        let stored = try storedTextFile()
        let file = AttachedFile(file: stored.file, name: "Notiz.txt", kind: .text,
                                bytes: stored.bytes, chars: 6)
        let answer = makeBubble(files: [file],
                                fileRefs: [FileRef(name: "Notiz.txt", detail: "6 Zeichen",
                                                   via: .plain)])
        let files = mountView(answer.filesView, size: CGSize(width: 390, height: 200))
        try await settleHosted(files, milliseconds: 100)
        let refs = mountView(answer.fileRefsView, size: CGSize(width: 390, height: 120))
        try await settleHosted(refs, milliseconds: 100)
        XCTAssertEqual(answer.extractionKey, "file_local_plain")
    }

    func testTheVideoFileViewOffersSaving() async throws {
        documents.prepareDirectories()
        let stored = try XCTUnwrap(documents.store(data: Data([0, 0, 0, 0x18]) + Data("ftypisom".utf8),
                                                   fileExtension: "mp4"))
        let file = AttachedFile(file: stored.file, name: "GwenMobile-Video.mp4", kind: .video,
                                bytes: stored.bytes)
        let answer = makeBubble(files: [file])
        let controller = mountView(answer.filesView, size: CGSize(width: 390, height: 240))
        try await settleHosted(controller, milliseconds: 100)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 1000)).height, 40)
        XCTAssertEqual(FileSavePresenter.exportName("a/b:c.mp4", fallback: "x.mp4"), "a-b-c.mp4")
        XCTAssertEqual(FileSavePresenter.exportName("   ", fallback: "x.mp4"), "x.mp4")
    }

    func testSmokeTheCalendarAndReminderChipsDrawAndAct() async throws {
        EventKitReminderStore.accessStatusOverride = .denied
        CalendarService.accessStatusOverride = .denied
        let ref = CalendarRef(eventID: "ev-1", title: "Zahnarzt", start: Date())
        let reminder = ReminderRef(reminderID: "rem-1", title: "Milch", list: "Privat",
                                   due: Date(), allDay: false, place: nil)
        let answer = makeBubble()
        answer.openRemindersApp(at: 9)
        answer.openAppointment(ref)
        answer.openReminder(reminder)
        let calendar = mountView(answer.calendarView(ref), size: CGSize(width: 390, height: 140))
        try await settleHosted(calendar, milliseconds: 100)
        let reminders = mountView(answer.reminderView(reminder), size: CGSize(width: 390, height: 140))
        try await settleHosted(reminders, milliseconds: 100)
        EventKitReminderStore.accessStatusOverride = nil
        CalendarService.accessStatusOverride = nil
        dismissPresentedSheets()
    }

    func testSmokeTheCalendarAndReminderChipsWithFullAccess() async throws {
        CalendarService.accessStatusOverride = .fullAccess
        EventKitReminderStore.accessStatusOverride = .fullAccess
        let ref = CalendarRef(eventID: "unbekannt", title: "Termin", start: Date())
        let reminder = ReminderRef(reminderID: "unbekannt", title: "Aufgabe", list: "Privat",
                                   due: nil, allDay: false, place: "Zuhause")
        let answer = makeBubble()
        answer.openAppointment(ref)
        answer.openReminder(reminder)
        CalendarService.accessStatusOverride = nil
        EventKitReminderStore.accessStatusOverride = nil
    }

    func testSmokeTheReminderOfferDrawsAndCallsBack() async throws {
        var offered: UUID?
        let message = ChatMessage(role: .assistant, text: "Scan")
        var offerBubble = Bubble(message: message, media: media, documents: documents,
                                 photos: PhotoLibraryWriter(library: FakePhotoLibrary()))
        offerBubble.reminderOffer = ScanReminderOffer(title: "Rechnung zahlen", due: Date())
        offerBubble.onReminderOffer = { id, _ in offered = id }
        if let offer = offerBubble.reminderOffer {
            let view = offerBubble.reminderOfferView(offer)
            let controller = mountView(view, size: CGSize(width: 390, height: 200))
            try await settleHosted(controller, milliseconds: 150)
            for action in MirrorTap.actions(in: view) { action() }
        }
        _ = offered
        let withoutID = Bubble(text: "ohne Kennung", isUser: false)
        if let offer = withoutID.reminderOffer {
            for action in MirrorTap.actions(in: withoutID.reminderOfferView(offer)) { action() }
        }
    }

    func testThePictureActionsDrawAndOpen() async throws {
        let att = try storedAttachment()
        var previewed: Attachment?
        var openedPicture: WebPicture?
        var edited: Attachment?
        var answer = makeBubble()
        answer.onPreview = { previewed = $0 }
        answer.onOpenPicture = { openedPicture = $0 }
        answer.onEdit = { edited = $0 }
        answer.openPreview(att)
        answer.shareImage(att)
        answer.shareImage(Attachment(file: "weg.jpg"))
        let picture = WebPicture(file: att.file, pageURL: "tel:0171",
                                 fullURL: "https://bild.test/a.jpg", title: "Bild",
                                 domain: "seite.test")
        answer.openPicture(picture)
        answer.openPictureSource(picture)
        let emptyPage = WebPicture(file: att.file, pageURL: "", fullURL: "tel:0172",
                                   title: "Bild", domain: "bild.test")
        answer.openPictureSource(emptyPage)
        let actions = mountView(answer.imageActions(att, library: true),
                                size: CGSize(width: 300, height: 260))
        try await settleHosted(actions, milliseconds: 150)
        for action in MirrorTap.actions(in: answer.imageActions(att, library: true)) { action() }
        XCTAssertEqual(previewed, att)
        XCTAssertEqual(openedPicture, picture)
        _ = edited
        dismissPresentedSheets()
    }

    func testSmokeTheSourceReportingAndAddressOpening() {
        let source = WebSource(title: "Quelle", url: "tel:0123456789",
                               domain: "example.com")
        let answer = makeBubble(sources: [source])
        answer.openSource(source)
        answer.openWebAddress("tel:0171")
        answer.openWebAddress("nicht wirklich eine adresse")
        answer.reportSource(source)
        answer.withdrawSource(source)
    }

    func testTheAnswerURLsRoutePhoneClaimsAndSources() {
        let source = WebSource(title: "Quelle", url: "tel:0173",
                               domain: "example.com")
        var review = SourceReview()
        review.results = [SourceReview.ClaimResult(claim: "Aussage", verdict: .unsupported,
                                                   sources: [], contradicts: [])]
        var message = ChatMessage(role: .assistant, text: "Aussage [1]")
        message.sources = [source]
        message.sourceReview = review
        var answer = Bubble(message: message, media: media, documents: documents,
                            photos: PhotoLibraryWriter(library: FakePhotoLibrary()))
        var called: DialNumber?
        answer.onCall = { called = $0 }
        XCTAssertTrue(answer.handleAnswerURL(URL(string: "tel:0171")!))
        XCTAssertEqual(called?.digits, "0171")
        XCTAssertTrue(answer.handleAnswerURL(URL(string: "gwen-claim://0")!))
        _ = answer.claimNote
        XCTAssertTrue(answer.handleAnswerURL(URL(string: "gwen-source://1")!))
        XCTAssertFalse(answer.handleAnswerURL(URL(string: "gwen-source://7")!))
        XCTAssertFalse(answer.handleAnswerURL(URL(string: "https://anderes.test")!))
    }

    func testTheMultiPartAnswerBodyDraws() async throws {
        let multi = makeBubble(text: "Erklärung\n```swift\nlet wert = 1\n```\nEnde")
        XCTAssertGreaterThan(multi.answerParts.count, 1)
        let body = mountView(multi.answerBody, size: CGSize(width: 390, height: 700))
        try await settleHosted(body, milliseconds: 200)
        let single = makeBubble(text: "Nur Fließtext")
        let one = mountView(single.answerBody, size: CGSize(width: 390, height: 200))
        try await settleHosted(one, milliseconds: 120)
        let user = makeBubble(text: "Frage", user: true)
        let userBody = mountView(user.answerBody, size: CGSize(width: 390, height: 200))
        try await settleHosted(userBody, milliseconds: 120)
    }

    func testTheWholeBubbleDrawsWithFilesAndSources() async throws {
        let stored = try storedTextFile()
        let file = AttachedFile(file: stored.file, name: "Notiz.txt", kind: .text,
                                bytes: stored.bytes, chars: 6)
        let source = WebSource(title: "Quelle", url: "https://example.com/a", domain: "example.com")
        let ocrFile = OcrTextStore.name(imageDate: Date())
        OcrTextCache.shared.remember("Text", for: ocrFile)
        let answer = makeBubble(text: "Antwort [1] mit Datei",
                                files: [file], ocr: [OcrFile(file: ocrFile, chars: 4)],
                                fileRefs: [FileRef(name: "Notiz.txt", via: .plain)],
                                sources: [source])
        let controller = mountView(answer, size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(controller.view.window)
    }
}
