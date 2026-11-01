@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class PictureGalleryTests: GwenTestCase {
    private func picture(_ number: Int) -> WebPicture {
        WebPicture(file: "img_gallery_\(number).jpg",
                   pageURL: "https://q\(number).test/seite",
                   fullURL: "https://cdn.q\(number).test/original.jpg",
                   title: "Bild \(number)", domain: "q\(number).test")
    }

    private func gallery(_ count: Int, shown: Int = ImagePolicy.galleryInitialItems,
                         exhausted: Bool = false) -> PictureGallery {
        PictureGallery(query: "cary elwes", pictures: (1...count).map { picture($0) },
                       shown: shown, nextOffset: count + 1, exhausted: exhausted)
    }

    func testTheFirstAnswerNeverShowsMoreThanTheBudgetAllows() {
        let full = gallery(ImagePolicy.galleryMaxStored)
        XCTAssertEqual(full.visiblePictures.count, ImagePolicy.galleryInitialItems)
        XCTAssertEqual(full.hiddenCount, ImagePolicy.galleryMaxStored - ImagePolicy.galleryInitialItems)
        XCTAssertTrue(full.hiddenCount > 0 || !full.exhausted)
    }

    func testRevealingMoreStopsAtThePicturesAlreadyOnTheMessage() {
        let small = gallery(5)
        let more = small.revealingMore()
        XCTAssertEqual(more.visiblePictures.count, 5)
        XCTAssertEqual(more.hiddenCount, 0)
        XCTAssertTrue(more.hiddenCount > 0 || !more.exhausted, "die nächste Seite ist noch nicht geholt")
    }

    func testAnExhaustedAndFullyShownGalleryOffersNoMoreButton() {
        let ended = gallery(4, shown: 12, exhausted: true)
        XCTAssertFalse(ended.hiddenCount > 0 || !ended.exhausted)
        XCTAssertEqual(ended.visiblePictures.count, 4)
    }

    func testMergingAppendsTheNewRoundAndKeepsWhatIsAlreadyStored() {
        let first = gallery(3)
        let round = PictureRound(pictures: [picture(3), picture(4)], nextOffset: 25,
                                exhausted: false, failures: 1)
        let merged = first.merging(round)
        XCTAssertEqual(merged.pictures.map(\.title), ["Bild 1", "Bild 2", "Bild 3", "Bild 4"])
        XCTAssertEqual(merged.visiblePictures.count, 4, "was nachgeladen wurde, ist auch zu sehen")
        XCTAssertEqual(merged.nextOffset, 25)
        XCTAssertFalse(merged.exhausted)
        XCTAssertEqual(merged.query, first.query)
    }

    func testTheGalleryNamesItsFilesAndItsSources() {
        let items = gallery(2)
        XCTAssertEqual(items.files, ["img_gallery_1.jpg", "img_gallery_2.jpg"])
        XCTAssertEqual(items.chipSources.map(\.domain), ["q1.test", "q2.test"])
        XCTAssertEqual(items.chipSources.first?.url, "https://q1.test/seite")
    }

    func testTheSourceChipsStayReadable() {
        let repeated = PictureGallery(query: "a", pictures: (1...10).map { index in
            let domain = "q\(index % 3).test"
            return WebPicture(file: "f\(index)", pageURL: "https://\(domain)/s",
                              fullURL: "https://cdn.\(domain)/o.jpg", title: "t\(index)", domain: domain)
        })
        XCTAssertEqual(repeated.chipSources.map(\.domain), ["q1.test", "q2.test", "q0.test"])
        let many = PictureGallery(query: "a", pictures: (1...12).map { index in
            WebPicture(file: "g\(index)", pageURL: "https://n\(index).test/s",
                       fullURL: "https://cdn.n\(index).test/o.jpg", title: "t\(index)",
                       domain: "n\(index).test")
        })
        XCTAssertEqual(many.chipSources.count, ImagePolicy.gallerySourceChips)
    }

    private func message(_ gallery: PictureGallery?) -> ChatMessage {
        ChatMessage(role: .assistant, text: "Antwort", model: "m", elapsed: 1, gallery: gallery)
    }

    func testTheGallerySurvivesTheConversationFile() throws {
        var conversation = Conversation(title: "Bilder")
        conversation.messages = [message(gallery(3))]
        let data = try JSONEncoder().encode([conversation])
        let back = try JSONDecoder().decode([Conversation].self, from: data)
        let restored = try XCTUnwrap(back.first?.messages.first?.gallery)
        XCTAssertEqual(restored.pictures.count, 3)
        XCTAssertEqual(restored.nextOffset, 4)
        XCTAssertEqual(restored.visiblePictures.map(\.file),
                       ["img_gallery_1.jpg", "img_gallery_2.jpg", "img_gallery_3.jpg"])
    }

    func testACorruptShownValueCannotOverflowTheGallery() throws {
        let stored = #"{"query":"a","shown":9223372036854775807,"pictures":[]}"#
        let gallery = try JSONDecoder().decode(PictureGallery.self, from: Data(stored.utf8))
        XCTAssertEqual(gallery.shown, ImagePolicy.galleryInitialItems)
        XCTAssertEqual(gallery.revealingMore().shown, ImagePolicy.galleryInitialItems)
    }

    func testAnOldConversationWithoutAGalleryStillReads() throws {
        let stored = #"[{"messages":[{"role":"assistant","text":"nur text","images":[]}]}]"#
        let back = try JSONDecoder().decode([Conversation].self, from: Data(stored.utf8))
        XCTAssertNil(back.first?.messages.first?.gallery)
        XCTAssertTrue(back.first?.messages.first?.galleryFiles.isEmpty ?? false)
    }

    func testADamagedGalleryLeavesTheMessageUsable() throws {
        let stored = #"[{"messages":[{"role":"assistant","text":"t","gallery":{"query":5,"pictures":"kaputt"}}]}]"#
        let back = try JSONDecoder().decode([Conversation].self, from: Data(stored.utf8))
        let message = try XCTUnwrap(back.first?.messages.first)
        XCTAssertEqual(message.text, "t")
        XCTAssertTrue(message.gallery == nil || message.gallery?.pictures.isEmpty == true)
    }

    func testEmptyPicturesAreNoGallery() throws {
        let stored = #"[{"messages":[{"role":"assistant","text":"t","gallery":{"query":"a","pictures":[]}}]}]"#
        let back = try JSONDecoder().decode([Conversation].self, from: Data(stored.utf8))
        XCTAssertNil(back.first?.messages.first?.gallery)
    }

    func testTheGalleryNeverEntersThePictureContextOfTheModel() throws {
        let turn = ConversationMemory.turn(from: [message(gallery(3))]) { _ in Data([8, 8]) }
        XCTAssertEqual(turn.pictureCount, 0, "Webfundstücke dürfen nicht als Chatbild weitergegeben werden")
        XCTAssertTrue(turn.pictureFiles.isEmpty)
        XCTAssertFalse(turn.needsVision)
    }

    func testTheMessageKeepsGalleryFilesApartFromItsOwnAttachments() {
        let attached = ChatMessage(role: .user, text: "eigenes", images: [Attachment(file: "img_eigen.jpg")])
        XCTAssertEqual(attached.imageFiles, ["img_eigen.jpg"])
        XCTAssertEqual(attached.storedImageFiles, ["img_eigen.jpg"])
        let answer = message(gallery(2))
        XCTAssertTrue(answer.imageFiles.isEmpty)
        XCTAssertEqual(answer.storedImageFiles, ["img_gallery_1.jpg", "img_gallery_2.jpg"])
        XCTAssertTrue(answer.hasGallery)
    }

    func testTheAnswerLineNamesCountAndQuestionAndStaysFreeOfGeneratorWords() {
        let text = ChatView.galleryAnswer(gallery: gallery(3), failures: 0)
        XCTAssertTrue(text.contains("3"), text)
        XCTAssertTrue(text.contains("cary elwes"), text)
        XCTAssertFalse(text.contains("erzeugt wurde"), text)
    }

    func testTheAnswerLineReportsWhatRefusedToLoad() {
        let text = ChatView.galleryAnswer(gallery: gallery(3), failures: 2)
        XCTAssertTrue(text.contains("5"), "3 von 5 müssen beide Zahlen nennen: \(text)")
        XCTAssertTrue(text.contains("3"), text)
    }
}

@MainActor
final class PictureGalleryRetentionTests: GwenTestCase {
    private func sandbox() -> (ChatStore, MediaStore) {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        return (store, media)
    }

    @discardableResult
    private func appendGallery(_ store: ChatStore, _ media: MediaStore,
                               count: Int) throws -> [String] {
        let files = (1...count).compactMap { _ in media.storeImageData(FakePictureData.jpeg()) }
        let pictures = files.enumerated().map { index, file in
            WebPicture(file: file, pageURL: "https://q\(index).test/s", fullURL: "https://q\(index).test/o.jpg",
                       title: "Bild \(index)", domain: "q\(index).test")
        }
        store.appendAssistant("Bilder", model: "m", elapsed: nil, to: try XCTUnwrap(store.currentID),
                              gallery: PictureGallery(query: "aurora", pictures: pictures))
        return files
    }

    func testGalleryPicturesCountAsReferencedFiles() throws {
        let (store, media) = sandbox()
        let files = try appendGallery(store, media, count: 3)
        XCTAssertEqual(Set(store.referencedFiles), Set(files))
        XCTAssertTrue(files.allSatisfy(media.hasImage))
    }

    func testDeletingTheMessageTrashesItsGalleryPictures() throws {
        let (store, media) = sandbox()
        let files = try appendGallery(store, media, count: 2)
        let conversation = try XCTUnwrap(store.currentID)
        let message = try XCTUnwrap(store.current?.messages.last)
        store.cleaner.deleteMessage(message.id, in: conversation)
        XCTAssertTrue(files.allSatisfy { !media.hasImage($0) }, "die Fundstücke bleiben als Leiche liegen")
    }

    func testTheInMemoryFeedKeepsGalleryPicturesOfTheOpenConversation() async throws {
        let (store, media) = sandbox()
        let files = try appendGallery(store, media, count: 2)
        store.images.load(files[0])
        await waitUntil { store.images.rendition(for: files[0]) != nil }
        store.newConversation()
        XCTAssertNil(store.images.rendition(for: files[0]), "ein verlassenes Bild verlässt auch den Speicher")
    }
}
