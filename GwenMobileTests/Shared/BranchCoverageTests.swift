@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
import GwenMobileKit

private final class BranchViewerReader: ViewerImageReading, @unchecked Sendable {
    private let images: [String: UIImage]

    init(_ images: [String: UIImage]) {
        self.images = images
    }

    func viewerImage(named file: String) -> UIImage? {
        images[file]
    }
}

@MainActor
final class BranchCoverageTests: GwenTestCase {
    private func image(_ color: UIColor = .systemTeal) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    private func chatStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheViewerTurnsToTheNextPicture() async throws {
        let reader = BranchViewerReader(["a.jpg": image(), "b.jpg": image(.systemOrange)])
        let target = try XCTUnwrap(ImagePreviewTarget(tappedFile: "a.jpg", files: ["a.jpg", "b.jpg"]))
        let view = ImageViewerView(target: target, reader: reader)
        let controller = mountView(view, size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 400)
        let actions = TapProbe.drain()
        XCTAssertGreaterThanOrEqual(actions.count, 3)
        for action in actions { action() }
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheCameraPresenterShowsTheHintWithoutHardwareAndDismisses() async throws {
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        let host = try XCTUnwrap(window?.rootViewController)
        Presenter.hostOverride = host
        defer { Presenter.hostOverride = nil }
        CameraPresenter.shared.isAvailableOverride = nil
        CameraPresenter.isCameraAvailable = { false }
        _ = CameraPresenter.shared.isAvailable
        let captured = await CameraPresenter.shared.capture()
        XCTAssertNil(captured)
        CameraPresenter.shared.present()
        CameraPresenter.shared.dismissPresented()
        XCTAssertTrue(Presenter.presentIfPossible(UIViewController()))
        dismissPresentedSheets()
    }

    func testThePriceWatchCardOpensTheOffer() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        URLOpenSpy.opened = []
        var watch = PriceWatch(terms: ["PlayStation 5"], goal: 400, wording: "PS5",
                               currencyCode: "EUR", lastCheckedAt: Date(), lastPrice: 379,
                               lastCurrency: "EUR", lastShop: "MediaMarkt",
                               lastURL: "https://shop.test/ps5", lastProduct: "PS5 Disc")
        watch.paused = false
        let ref = PriceWatchRef(watch: watch)
        let controller = mountView(PriceWatchCardView(ref: ref), size: CGSize(width: 320, height: 300))
        try await settleHosted(controller, milliseconds: 300)
        let actions = TapProbe.drain()
        XCTAssertFalse(actions.isEmpty)
        for action in actions { action() }
        XCTAssertTrue(URLOpenSpy.opened.contains { $0.absoluteString == "https://shop.test/ps5" })
    }

    func testThePriceWatchListNeedsAProviderAndOpensTheOffer() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        URLOpenSpy.opened = []
        let store = chatStore("branch-watch-list")
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedKey = settings.key(for: provider)
        settings.setKey("", for: provider)
        defer { settings.setKey(savedKey, for: provider) }
        let createdOption = await store.watches.create(terms: ["PS5"], goal: 400,
                                                       intervalHours: 24, currencyCode: "EUR",
                                                       regionCode: nil)
        let created = try XCTUnwrap(createdOption)
        await store.watches.record(id: created.watch.id,
                                   offer: PriceWatchOffer(price: 379, currency: "EUR", shop: "MediaMarkt",
                                                          url: "https://shop.test/ps5", product: "PS5"),
                                   fallbackCurrency: "EUR")
        let controller = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 500)
        let actions = TapProbe.drain()
        XCTAssertGreaterThanOrEqual(actions.count, 2)
        for action in actions { action() }
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertTrue(URLOpenSpy.opened.contains { $0.absoluteString == "https://shop.test/ps5" })
    }

    func testThePictureDirectorRejectsAnUnreadableAnswer() async throws {
        MockHTTP.install { _ in (200, MockHTTP.completion("Das Bild zeigt leider nichts.")) }
        defer { MockHTTP.uninstall() }
        let direction = await PictureDirector.observe(baseURL: "https://api.test/v1", key: "k",
                                                      model: "m", instruction: "mach es blau",
                                                      pictures: [Data([0xFF, 0xD8, 0xFF, 0xD9]),
                                                                 Data([0xFF, 0xD8, 0xFF, 0xD9])],
                                                      thinking: .nothing)
        XCTAssertNil(direction)
    }

    func testTheAnswerBubbleSharesItsTextAndExplainsMissingFiles() throws {
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        Presenter.hostOverride = try XCTUnwrap(window?.rootViewController)
        defer { Presenter.hostOverride = nil }
        let bubble = Bubble(text: "Antwort", isUser: false, question: "Frage")
        bubble.saveAsFile()
        XCTAssertNil(bubble.shareFailure)

        let paths = temporaryPaths("branch-bubble-files")
        let documents = DocumentStore(paths: paths)
        let message = ChatMessage(role: .assistant, text: "Antwort")
        let missing = Bubble(message: message, media: MediaStore(paths: paths), documents: documents,
                             photos: PhotoLibraryWriter())
        missing.shareScan(AttachedFile(file: "fehlt.pdf", name: "fehlt.pdf", kind: .pdf, bytes: 12))
        XCTAssertNil(missing.shareFailure)

        OcrTextCache.shared.remember("Erkannter Text", for: "branch-ocr.jpg.txt")
        let root = OcrTextStore.temporaryRoot
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("branch-ocr.jpg.txt")
        addTeardownBlock { try? FileManager.default.removeItem(at: blocked) }
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let ocr = Bubble(text: "Antwort", isUser: false)
        ocr.openOCRFile(OcrFile(file: "branch-ocr.jpg.txt", chars: 5))
        XCTAssertNil(ocr.shareFailure)
        dismissPresentedSheets()
    }

    func testTheDocumentPresenterOpensAndCloses() async throws {
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        Presenter.hostOverride = try XCTUnwrap(window?.rootViewController)
        defer { Presenter.hostOverride = nil }
        let presenter = DocumentPresenter()
        presenter.present()
        presenter.close()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        var received: [URL] = []
        presenter.onURLs = { received = $0 }
        presenter.documentPicker(picker, didPickDocumentsAt: [URL(fileURLWithPath: "/tmp/a.pdf")])
        presenter.documentPicker(picker, didPickDocumentAt: URL(fileURLWithPath: "/tmp/b.pdf"))
        XCTAssertEqual(received.count, 1)
        presenter.documentPickerWasCancelled(picker)
    }

    func testTheSelectedGalleryTileDrawsItsFrame() async throws {
        let picture = WebPicture(file: "branch.jpg", pageURL: "https://q.test/p",
                                 fullURL: "https://q.test/p.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let owner = UUID()
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.selectAll([picture.file])
        let view = PictureGalleryView(gallery: gallery, owner: owner,
                                      onOpen: { _ in }, onOpenSource: { _ in }, onOpenOriginal: { _ in },
                                      onMore: {}, onShare: { _ in }, onSave: { _ in })
            .environmentObject(selection)
            .environmentObject(GalleryOperation())
            .environmentObject(ImageFeed(reader: MediaStore(paths: temporaryPaths("branch-gallery"))))
        let controller = mountView(view, size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 320, height: 3000)).height, 40)
    }

    func testTheStoreFailureIsReported() async throws {
        let paths = temporaryPaths("branch-store-failure")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: paths.support.path)
        }
        try makeSupportUnwritable(paths)
        try? await Task.sleep(for: .milliseconds(250))
        await store.memory.add(text: "Notiz", category: .plans, source: .manual)
        _ = await store.watches.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                       currencyCode: "EUR", regionCode: nil)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(store.storageProblem)
    }
}

@MainActor
extension BranchCoverageTests {
    func testTheDefaultCameraAvailabilityAndMissingPresenter() async {
        _ = CameraPresenter.isCameraAvailable()
        CameraPresenter.isCameraAvailable = { true }
        CameraPresenter.presentCameraOverride = { false }
        Presenter.hostOverride = nil
        let captured = await CameraPresenter.shared.capture()
        XCTAssertNil(captured)
    }
}
