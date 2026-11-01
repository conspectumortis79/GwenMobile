@testable import GwenMobileDevice
import XCTest
import GwenMobileKit

final class ChatInputTests: XCTestCase {

    func testReturnSendsTheTypedMessageWithoutTheNewline() {
        XCTAssertEqual(ChatView.messageAfterReturn("Wie geht es dir?\n"), "Wie geht es dir?")
        XCTAssertEqual(ChatView.messageAfterReturn("  Hallo  \n"), "Hallo")
    }

    func testTextWithoutReturnStaysInTheField() {
        XCTAssertNil(ChatView.messageAfterReturn("Wie geht es dir?"))
        XCTAssertNil(ChatView.messageAfterReturn(""))
        XCTAssertNil(ChatView.messageAfterReturn("zeile eins\nzeile zwei"))
    }

    func testReturnOnAnEmptyFieldSendsNothing() {
        XCTAssertNil(ChatView.messageAfterReturn("\n"))
        XCTAssertNil(ChatView.messageAfterReturn("   \n"))
        XCTAssertNil(ChatView.messageAfterReturn("\n\n"))
    }

    func testTheMessageSentByReturnKeepsItsOwnLineBreaks() {
        XCTAssertEqual(ChatView.messageAfterReturn("Erste Zeile\nZweite Zeile\n"),
                       "Erste Zeile\nZweite Zeile")
    }

    func testTheStrippedMessageCannotTriggerAnotherSend() {
        for typed in ["Hallo\n", "a\nb\n", " \n"] {
            guard let message = ChatView.messageAfterReturn(typed) else { continue }
            XCTAssertNil(ChatView.messageAfterReturn(message), "\(message) würde gleich nochmal senden")
        }
    }
}
