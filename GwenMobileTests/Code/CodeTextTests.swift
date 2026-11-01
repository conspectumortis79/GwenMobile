@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CodeTextTests: GwenTestCase {
    func testProseAndOneFencedFileBecomeSegmentsInTheirOwnOrder() {
        let answer = """
        Hier ist Tetris als eine Datei.

        ```html
        <!doctype html>
        <html lang="de">
        </html>
        ```

        Viel Spaß beim Spielen.
        """
        let parts = CodeText.segments(from: answer)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0].prose, "Hier ist Tetris als eine Datei.")
        guard let block = parts[1].code else {
            XCTFail("der Mittelteil muss ein Codeblock sein")
            return
        }
        XCTAssertEqual(block.language, .html)
        XCTAssertEqual(block.lineCount, 3)
        XCTAssertEqual(block.code, "<!doctype html>\n<html lang=\"de\">\n</html>")
        XCTAssertEqual(parts[2].prose, "Viel Spaß beim Spielen.")
    }

    func testAStillOpenFenceStreamsAsCodeUntilItCloses() {
        let growing = "Der Code:\n\n```python\nprint('hallo')\nprint('welt')"
        let parts = CodeText.segments(from: growing)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last?.code?.language, .python)
        XCTAssertEqual(parts.last?.code?.lines, ["print('hallo')", "print('welt')"])
    }

    func testAWishWithoutAFenceStaysOneProseSegment() {
        let parts = CodeText.segments(from: "Berlin hat 3,8 Millionen Einwohner.")
        XCTAssertEqual(parts.count, 1)
        XCTAssertNotNil(parts[0].prose)
        XCTAssertTrue(CodeText.blocks(in: "Berlin hat 3,8 Millionen Einwohner.").isEmpty)
    }

    func testSingleBackticksAreNotAFile() {
        let parts = CodeText.segments(from: "Benutze `useState` und `useEffect` korrekt.")
        XCTAssertEqual(parts.count, 1)
        XCTAssertNil(parts[0].code)
    }

    func testALanguagelessFenceStillFindsTheWebPage() {
        let parts = CodeText.segments(from: "```html\n<!DOCTYPE html>\n<title>T</title>\n```\nnur das")
        XCTAssertEqual(parts.first?.code?.language, .html)
        let plain = CodeText.segments(from: "```\n<!doctype html>\n<body>x</body>\n```")
        XCTAssertEqual(plain.first?.code?.language, .html)
        let unknown = CodeText.segments(from: "```\nGELDMENGEN = [1, 2, 3]\n```")
        XCTAssertEqual(unknown.first?.code?.language, .text)
    }

    func testFenceAliasesMapOntoTheSameLanguage() {
        XCTAssertEqual(CodeText.segments(from: "```js\nlet a = 1\n```").first?.code?.language, .javascript)
        XCTAssertEqual(CodeText.segments(from: "```typescript\nlet a: number = 1\n```").first?
                       .code?.language, .typescript)
        XCTAssertEqual(CodeText.segments(from: "```bash\nls\n```").first?.code?.language, .shell)
    }

    func testIndentationAndTrailingSpacesDoNotHideAFence() {
        let parts = CodeText.segments(from: "  ```html\n<p>a</p>\n  ``` ")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].code?.language, .html)
        XCTAssertEqual(parts[0].code?.lines, ["<p>a</p>"])
    }

    func testEmptyFencesAreNoFile() {
        let parts = CodeText.segments(from: "```\n```")
        XCTAssertFalse(parts.contains { $0.code != nil })
        XCTAssertTrue(CodeText.blocks(in: "```\n```").isEmpty)
    }

    func testEveryFileOfTheAnswerKeepsItsOwnLanguageAndOrder() {
        let answer = """
        ```html
        <!doctype html>
        <body>spiel</body>
        </html>
        ```
        ```css
        body { color: red }
        ```
        """
        let blocks = CodeText.blocks(in: answer)
        XCTAssertEqual(blocks.map(\.language), [.html, .css])
        XCTAssertEqual(blocks.first?.lineCount, 3)
        XCTAssertTrue(CodeText.blocks(in: "kein code").isEmpty)
    }

    func testCodeKeepsItsOwnIndentationAndBlankLinesInsideTheFence() {
        let parts = CodeText.segments(from: "```swift\nfunc a() {\n\n    print(1)\n}\n```")
        XCTAssertEqual(parts.first?.code?.code, "func a() {\n\n    print(1)\n}")
    }

    func testAFenceInsideTheAnswerNeverEatsTheProseAfterIt() {
        let answer = "Vorher.\n\n```\nlet a = 1\n```\n\nNachher."
        let parts = CodeText.segments(from: answer)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.first?.prose, "Vorher.")
        XCTAssertEqual(parts.last?.prose, "Nachher.")
    }

    func testANonProseSegmentHasNoProseText() {
        let parts = CodeText.segments(from: "```\nlet x = 1\n```")
        XCTAssertEqual(parts.count, 1)
        XCTAssertNil(parts.first?.prose)
    }
}
