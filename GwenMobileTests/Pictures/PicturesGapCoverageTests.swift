@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreImage
import UIKit
import XCTest
import GwenMobileKit

private struct DeliveredPictures: ImageGenerating {
    let pictures: [GeneratedPicture]

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        pictures
    }
}

@MainActor
final class PicturesGapCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testTheGalleryShortcutLine() {
        let plan = GalleryBarPlan.make(selected: 1, total: 2, progress: nil, result: nil)
        XCTAssertEqual(plan.shortcutLine, L.t("pictures_shortcuts"))
    }

    func testTheRealIdleCountdownFiresAndCancels() async {
        let countdown = TaskIdleCountdown()
        let fired = LockedValue(0)
        countdown.restart(after: .milliseconds(10)) { fired.mutate { $0 += 1 } }
        await waitUntil { fired.current == 1 }
        countdown.restart(after: .seconds(30)) { fired.mutate { $0 += 1 } }
        countdown.cancel()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(fired.current, 1)
        countdown.cancel()
    }

    func testTheTapModifierProbeReadsEveryModifier() {
        let probe = TapModifierProbe()
        XCTAssertEqual(probe.mode, .plain)
        probe.note(.command)
        XCTAssertEqual(probe.mode, .adding)
        probe.note(.shift)
        XCTAssertEqual(probe.mode, .range)
        probe.note(.alternate)
        XCTAssertEqual(probe.mode, .saving)
        probe.note([.command, .shift])
        XCTAssertEqual(probe.mode, .adding)
    }

    func testTheTapProbeViewForwardsItsFlags() {
        let probe = TapModifierProbe()
        let view = GalleryTapProbeView(frame: .zero)
        view.onFlags = { probe.note($0) }
        view.touchesBegan([], with: nil)
        XCTAssertEqual(probe.mode, .plain)
        probe.note(.alternate)
        XCTAssertEqual(probe.mode, .saving)
    }

    func testTheOcrStoreNamesAndTemporaryFiles() {
        let paths = temporaryPaths("ocr-gap")
        XCTAssertTrue(OcrTextStore.documentsURL(for: "text_x.jpg.txt", paths: paths).path.hasSuffix("text_x.jpg.txt"))
        let url = OcrTextStore.temporaryFile(named: "gap-\(UUID().uuidString).txt", text: "hallo")
        XCTAssertNotNil(url)
        if let url { try? FileManager.default.removeItem(at: url) }
        let blocked = OcrTextStore.temporaryRoot.appendingPathComponent("gap-dir-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        XCTAssertNil(OcrTextStore.temporaryFile(named: blocked.lastPathComponent, text: "hallo"))
        try? FileManager.default.removeItem(at: blocked)
        OcrTextStore.removeStoredText()
    }

    func testThePictureSearchRequestsAndParsesHits() throws {
        let request = try BingPictureSearch.request(query: "  Katzen  ", offset: 0)
        XCTAssertFalse(request.url?.query()?.contains("first=0") ?? false)
        XCTAssertTrue(request.url?.query()?.contains("first=1") ?? false)
        let turl = "https://tse1.mm.bing.net?id=OIP.abc"
        let thumb = try XCTUnwrap(BingPictureSearch.thumbnailURL(from: turl))
        XCTAssertTrue(thumb.contains("/th?id=OIP.abc"))
        XCTAssertNil(BingPictureSearch.thumbnailURL(from: "http://tse.test?id=x"))
        XCTAssertNil(BingPictureSearch.thumbnailURL(from: "https://tse.test?id="))
        XCTAssertEqual(BingPictureSearch.thumbnailURL(from: "https://tse.test/th?id=x"),
                       "https://tse.test/th?id=x&w=\(ImagePolicy.galleryThumbPixel)")
        let murlOnly = #"{"turl":"https://tse1.mm.bing.net/?id=OIP.abc","murl":"https://seite.test/bild"}"#
        let hit = try XCTUnwrap(BingPictureSearch.hit(fromJSON: murlOnly))
        XCTAssertEqual(hit.pageURL, "https://seite.test/bild")
        XCTAssertEqual(hit.domain, "seite.test")
        let badPage = #"{"turl":"https://tse1.mm.bing.net/?id=OIP.abc","purl":"keine url"}"#
        XCTAssertNil(BingPictureSearch.hit(fromJSON: badPage))
        XCTAssertNil(BingPictureSearch.hit(fromJSON: "kein json"))
        let html = "<img m=\"{&quot;turl&quot;:&quot;https://tse1.mm.bing.net/?id=OIP.abc&quot;,"
            + "&quot;murl&quot;:&quot;https://seite.test/bild&quot;}\">"
        let hits = BingPictureSearch.hits(from: html)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.domain, "seite.test")
        XCTAssertTrue(BingPictureSearch.hits(from: "<div m=\"kein json\"></div>").isEmpty)
    }

    func testTheTextRecognitionEntryPoints() {
        XCTAssertNil(TextRecognizing.recognize(data: Data([0x00, 0x01]), languages: ["en-US"]))
        XCTAssertNil(TextRecognizing.recognize(image: UIImage(ciImage: CIImage(color: .red)),
                                               languages: ["en-US"]))
        XCTAssertNil(TextRecognizing.recognize(image: FakePicture.make(), languages: ["en-US"]))
        XCTAssertNil(TextRecognizing.text(from: nil))
        XCTAssertNil(TextRecognizing.text(from: []))
        L.apply(.es)
        XCTAssertEqual(TextRecognizing.languages.first, "es-ES")
        L.apply(.fr)
        XCTAssertEqual(TextRecognizing.languages.first, "fr-FR")
        L.apply(.de)
        XCTAssertEqual(TextRecognizing.languages.first, "de-DE")
        L.apply(.en)
    }

    func testTheRecognizedTextComesBackFromARenderedPicture() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 140)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 360, height: 140))
            ("HALLO WELT" as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
                .font: UIFont.systemFont(ofSize: 56),
                .foregroundColor: UIColor.black,
            ])
        }
        let text = TextRecognizing.recognize(image: image, languages: ["en-US", "de-DE"])
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("HALLO") ?? false, text ?? "")
        let fromData = try TextRecognizing.recognize(data: XCTUnwrap(image.pngData()),
                                                     languages: ["en-US", "de-DE"])
        XCTAssertTrue(fromData?.contains("HALLO") ?? false, fromData ?? "")
    }

    func testTheImageDeliveryStoresInlinePictures() async throws {
        let media = scratchMediaStore()
        let png = try XCTUnwrap(FakePicture.make().pngData())
        let delivery = ImageDelivery(media: media, backend: DeliveredPictures(pictures: [.inline(png)]))
        let attachments = try await delivery.makePicture(baseURL: "https://q.test", key: "k",
                                                        model: "m", prompt: "p")
        XCTAssertEqual(attachments.count, 1)
        let stored = try await delivery.store([.inline(png)])
        XCTAssertEqual(stored.count, 1)
        let empty = ImageDelivery(media: media, backend: DeliveredPictures(pictures: []))
        do {
            _ = try await empty.makePicture(baseURL: "https://q.test", key: "k", model: "m", prompt: "p")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheMonochromeConversion() throws {
        let png = try XCTUnwrap(FakePicture.make().pngData())
        XCTAssertNotNil(ImageDelivery.monochrome(png))
        XCTAssertNil(ImageDelivery.monochrome(Data([1, 2, 3])))
    }

    func testTheDashScopeBackendReturnsRemoteURLs() async throws {
        MockHTTP.install { _ in
            (200, Data(#"{"choices":[{"message":{"content":[{"image":"https://cdn.test/a.png"}]}}]}"#.utf8))
        }
        let pictures = try await DashScopeImageBackend().generate(baseURL: "https://q.test/v1", key: "k",
                                                                 model: "m", prompt: "p",
                                                                 inputImages: [], isEdit: false)
        XCTAssertEqual(pictures, [.remote(try XCTUnwrap(URL(string: "https://cdn.test/a.png")))])
    }

    func testTheZoomViewCoderInitializerReturnsNothing() {
        XCTAssertNil(ImageZoomScrollView(coder: NSKeyedArchiver(requiringSecureCoding: false)))
    }

    func testTheZoomViewIgnoresTheSameImageAndTheZeroBounds() {
        let image = FakePicture.make(CGSize(width: 200, height: 100))
        let view = ImageZoomScrollView(image: image)
        view.apply(image: image)
        XCTAssertTrue(view.subviews.contains { ($0 as? UIImageView)?.image === image })
        view.handleDoubleTap(at: .zero, animated: false)
        XCTAssertEqual(view.zoomScale, view.minimumZoomScale)
    }

    func testTheZoomViewDoubleTapSelectorAndLayout() {
        let view = ImageZoomScrollView(image: FakePicture.make(CGSize(width: 200, height: 100)))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        view.layoutIfNeeded()
        _ = view.perform(NSSelectorFromString("handleDoubleTap:"), with: UITapGestureRecognizer())
        view.layoutIfNeeded()
        XCTAssertGreaterThan(view.zoomScale, view.minimumZoomScale)
        let empty = ImageZoomScrollView(image: UIImage())
        empty.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        empty.layoutIfNeeded()
        XCTAssertEqual(empty.zoomScale, empty.minimumZoomScale)
    }
}
