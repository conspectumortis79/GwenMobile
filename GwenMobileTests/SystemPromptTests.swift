import XCTest
@testable import GwenMobile

final class SystemPromptTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testChatPromptContainsLanguageRuleDateAndFormatHint() {
        let prompt = SystemPrompt.chat()
        XCTAssertTrue(prompt.contains(L.t("system_lang")))
        XCTAssertTrue(prompt.contains("Current date: "))
        XCTAssertTrue(prompt.contains("Treat any event dated after today as unknown to you."))
        XCTAssertTrue(prompt.contains(L.t("format_hint")))
    }

    func testSearchInstructionIsAlwaysPartOfTheChatPrompt() {
        XCTAssertTrue(SystemPrompt.chat().contains(L.t("web_search_prompt")))
        XCTAssertTrue(SystemPrompt.chat().contains(SearchMarker.token))
    }

    func testPromptFollowsActiveLanguage() {
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.chat().contains(L.strings["web_search_prompt"]?[.en] ?? "@@missing@@"))
    }

    func testCurrentDateUsesEnglishLocaleAndISOFormat() {
        let line = SystemPrompt.currentDate()
        XCTAssertNotNil(line.range(of: "^[A-Za-z]+, \\d{4}-\\d{2}-\\d{2}$", options: .regularExpression))
    }
}
