@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatURLOpeningGapTests: GwenTestCase {
    private lazy var paths = temporaryPaths("chat-url-gap")
    private lazy var media = MediaStore(paths: paths)
    private lazy var documents = DocumentStore(paths: paths)

    private func makeBubble(sources: [WebSource] = []) -> Bubble {
        documents.prepareDirectories()
        media.prepareDirectories()
        var message = ChatMessage(role: .assistant, text: "Antwort")
        message.sources = sources
        return Bubble(message: message, media: media, documents: documents,
                      photos: PhotoLibraryWriter(library: FakePhotoLibrary()))
    }

    func testTheExternalOpenPathsWithASpy() {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        URLOpenSpy.opened = []
        let answer = makeBubble(sources: [WebSource(title: "Q", url: "https://example.com/a",
                                                    domain: "example.com")])
        answer.openWebAddress("https://example.com/b")
        answer.openSource(WebSource(title: "Q", url: "https://example.com/c", domain: "example.com"))
        answer.openPictureSource(WebPicture(file: "x.jpg", pageURL: "https://example.com/d",
                                            fullURL: "", title: "T", domain: "d"))
        answer.openCalendarApp()
        answer.openRemindersApp()
        answer.openRemindersApp(at: 0)
        XCTAssertFalse(URLOpenSpy.opened.isEmpty)
    }

    func testTheSystemURLOpenerWithASpy() async {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let opened = await SystemURLOpener().open(URL(string: "https://example.com")!)
        XCTAssertFalse(opened)
    }
}
