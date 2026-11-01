@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CodeLanguageTests: GwenTestCase {
    func testEveryLanguageNamesItsOwnFileAndFence() {
        for language in CodeLanguage.allCases {
            XCTAssertFalse(language.fileExtension.isEmpty)
            XCTAssertFalse(language.label.isEmpty)
            XCTAssertEqual(CodeLanguage(rawValue: language.rawValue), language)
        }
        XCTAssertEqual(CodeLanguage.html.fileExtension, "html")
        XCTAssertEqual(CodeLanguage.javascript.fileExtension, "js")
        XCTAssertEqual(CodeLanguage.python.fileExtension, "py")
        XCTAssertEqual(CodeLanguage.markdown.fileExtension, "md")
        XCTAssertEqual(CodeLanguage.csharp.fileExtension, "cs")
        XCTAssertEqual(CodeLanguage.cpp.fileExtension, "cpp")
        XCTAssertEqual(CodeLanguage.text.fileExtension, "txt")
        XCTAssertEqual(CodeLanguage.html.fenceTag, "html")
        XCTAssertEqual(CodeLanguage.text.fenceTag, "")
    }

    func testTheToolOnlyOffersLanguagesItCanName() {
        XCTAssertEqual(CodeLanguage.toolValues, CodeLanguage.allCases.map(\.rawValue))
        XCTAssertTrue(CodeLanguage.toolValues.contains("html"))
        for value in CodeLanguage.toolValues {
            XCTAssertEqual(CodeLanguage(toolValue: value).rawValue, value)
        }
    }

    func testWhatTheModelCallsALanguageStillLandsOnTheRightFile() {
        XCTAssertEqual(CodeLanguage(toolValue: "HTML"), .html)
        XCTAssertEqual(CodeLanguage(toolValue: " js "), .javascript)
        XCTAssertEqual(CodeLanguage(toolValue: "JavaScript"), .javascript)
        XCTAssertEqual(CodeLanguage(toolValue: "typescript"), .typescript)
        XCTAssertEqual(CodeLanguage(toolValue: "python3"), .python)
        XCTAssertEqual(CodeLanguage(toolValue: "C++"), .cpp)
        XCTAssertEqual(CodeLanguage(toolValue: "c#"), .csharp)
        XCTAssertEqual(CodeLanguage(toolValue: "golang"), .go)
        XCTAssertEqual(CodeLanguage(toolValue: "webpage"), .html)
        XCTAssertEqual(CodeLanguage(toolValue: "zsh"), .shell)
        XCTAssertEqual(CodeLanguage(toolValue: nil), .text)
        XCTAssertEqual(CodeLanguage(toolValue: ""), .text)
        XCTAssertEqual(CodeLanguage(toolValue: "unbekannt"), .text)
    }

    func testOnlyAWebPageFileCanOpenInABrowser() {
        XCTAssertTrue(CodeLanguage.html.opensInBrowser)
        XCTAssertFalse(CodeLanguage.text.opensInBrowser)
        XCTAssertFalse(CodeLanguage.python.opensInBrowser)
    }

    func testAnUnlabelledBlockIsOnlyReinterpretedWhenItProvesToBeAPage() {
        XCTAssertEqual(CodeLanguage.sniffed(from: "<!DOCTYPE html>\n<html></html>"), .html)
        XCTAssertEqual(CodeLanguage.sniffed(from: "\n\n  <html lang=\"de\">"), .html)
        XCTAssertNil(CodeLanguage.sniffed(from: "print('hallo')"))
        XCTAssertNil(CodeLanguage.sniffed(from: ""))
    }

    func testAnExplicitLabelWinsAndAPageUnderTextStillBecomesAPage() {
        XCTAssertEqual(CodeLanguage.resolved(fenceLabel: "swift", code: "print(1)"), .swift)
        XCTAssertEqual(CodeLanguage.resolved(fenceLabel: "html", code: "print(1)"), .html)
        XCTAssertEqual(CodeLanguage.resolved(fenceLabel: "txt", code: "<!doctype html>"), .html)
        XCTAssertEqual(CodeLanguage.resolved(fenceLabel: "", code: "print(1)"), .text)
        XCTAssertEqual(CodeLanguage.resolved(fenceLabel: nil, code: "x = 1"), .text)
    }
}
