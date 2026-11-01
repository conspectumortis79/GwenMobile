@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SystemPromptTests: GwenTestCase {
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

    func testTheChatPromptForbidsClaimingAPictureWasChanged() {
        let prompt = SystemPrompt.chat()
        XCTAssertTrue(prompt.contains(L.t("picture_honesty_prompt")), prompt)
        XCTAssertTrue(prompt.contains("only the app can"), "the rule has to be in the answer")
        XCTAssertTrue(prompt.contains("no new picture"), prompt)
    }

    func testThePictureHonestyRuleFollowsTheActiveLanguage() {
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.chat().contains(L.strings["picture_honesty_prompt"]?[.en] ?? "@@missing@@"))
        XCTAssertTrue(SystemPrompt.code(language: .html).contains("You cannot change a picture yourself"),
                      "auch der Code-Pfad antwortet mit Bildern im Spiel")
    }

    func testMemoryInstructionIsPartOfTheChatPrompt() {
        XCTAssertTrue(SystemPrompt.chat().contains(L.t("memory_prompt")))
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.chat().contains(L.strings["memory_prompt"]?[.en] ?? "@@missing@@"))
    }

    func testTheChatPromptTellsTheModelHowToMarkPhoneNumbers() {
        XCTAssertTrue(SystemPrompt.chat().contains(L.t("phone_link_hint")))
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.chat().contains(L.strings["phone_link_hint"]?[.en] ?? "@@missing@@"))
        XCTAssertFalse(SystemPrompt.code(language: .html).contains(L.t("phone_link_hint")),
                       "im Code darf keine Telefonnummer zum Link werden")
    }

    func testPromptFollowsActiveLanguage() {
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.chat().contains(L.strings["web_search_prompt"]?[.en] ?? "@@missing@@"))
    }

    func testTheCodePromptKeepsLanguageAndDateButLeavesTheChatFormattingBehind() {
        let prompt = SystemPrompt.code(language: .html)
        XCTAssertTrue(prompt.contains(L.t("system_lang")))
        XCTAssertTrue(prompt.contains("Current date: "))
        XCTAssertTrue(prompt.contains(L.t("code_prompt")))
        XCTAssertFalse(prompt.contains(L.t("format_hint")),
                       "Aufzählungszwang und Fettdruck zerstören die Datei")
        XCTAssertFalse(prompt.contains(SearchMarker.token))
        XCTAssertTrue(prompt.contains(SystemPrompt.fileProtocol),
                      "Text aus angehängten Dateien muss auch beim Code erklärt bleiben")
        XCTAssertTrue(prompt.contains(L.t("memory_prompt")),
                      "ein mitgeschicktes Foto bleibt auch beim Code eine Quelle")
    }

    func testTheCodePromptNamesTheExactFenceOfTheWishedLanguage() {
        XCTAssertTrue(SystemPrompt.code(language: .html).contains("```html"))
        XCTAssertTrue(SystemPrompt.code(language: .python).contains("```python"))
        XCTAssertNotEqual(SystemPrompt.code(language: .html), SystemPrompt.code(language: .css))
        L.apply(.en)
        XCTAssertTrue(SystemPrompt.code(language: .html)
                      .contains(L.strings["code_prompt"]?[.en] ?? "@@missing@@"))
    }

    func testCurrentDateUsesEnglishLocaleAndISOFormat() {
        let line = SystemPrompt.currentDate()
        XCTAssertNotNil(line.range(of: "^[A-Za-z]+, \\d{4}-\\d{2}-\\d{2}$", options: .regularExpression))
    }
}
