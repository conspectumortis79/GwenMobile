@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PromptLibraryTests: GwenTestCase {
    func testRenderReplacesEveryPlaceholder() {
        XCTAssertEqual(PromptLibrary.render("a {{one}} b {{two}}", ["one": "1", "two": "2"]), "a 1 b 2")
    }

    func testRenderLeavesUnknownPlaceholdersForTheCaller() {
        XCTAssertEqual(PromptLibrary.render("a {{one}}", [:]), "a {{one}}")
    }

    func testUnknownPromptLoadsEmpty() {
        XCTAssertEqual(PromptLibrary.text("dieser_prompt_existiert_nicht"), "")
    }

    func testEveryToolDescriptionComesFromTheBundle() {
        let tools = ToolRouter.tools(attachable: true)
        XCTAssertGreaterThanOrEqual(tools.count, 20)
        for tool in tools {
            let function = tool["function"] as? [String: Any]
            let description = function?["description"] as? String ?? ""
            XCTAssertFalse(description.isEmpty, function?["name"] as? String ?? "?")
            XCTAssertFalse(description.contains("{{"), function?["name"] as? String ?? "?")
        }
    }

    func testSystemBlockFillsEveryPlaceholder() {
        let context = SendContext()
        let block = ToolRouter.systemBlock(now: "2026-01-01 09:00", context: context, transcript: "")
        XCTAssertFalse(block.isEmpty)
        XCTAssertFalse(block.contains("{{"))
        XCTAssertTrue(block.contains("You decide what the app does"))
        XCTAssertTrue(block.contains(ToolRouter.answerTool))
        XCTAssertTrue(block.contains(ToolRouter.priceTool))
        XCTAssertTrue(block.contains(ToolRouter.weatherTool))
    }

    func testSystemBlockAppendsTheDynamicBlocks() {
        let context = SendContext(attachedImage: true, attachedFile: true, scannedDocument: true,
                                  documentReminder: true)
        let block = ToolRouter.systemBlock(now: "2026-01-01 09:00", context: context,
                                           transcript: "user: hi", catalog: "[#key] fact",
                                           eraseHistoryWord: "Verlauf löschen", document: "Rechnung 12 €")
        XCTAssertTrue(block.contains("MEMORY CATALOG"))
        XCTAssertTrue(block.contains("[#key] fact"))
        XCTAssertTrue(block.contains("SCANNED DOCUMENT"))
        XCTAssertTrue(block.contains("Rechnung 12 €"))
        XCTAssertTrue(block.contains("Recent conversation"))
        XCTAssertTrue(block.contains("Verlauf löschen"))
        XCTAssertTrue(block.contains("The user attached a new picture"))
        XCTAssertTrue(block.contains("A file is in play"))
        XCTAssertFalse(block.contains("{{"))
    }

    func testEveryToolArgumentDescriptionIsFilled() {
        let schemas = ToolRouter.tools(attachable: true) + ToolRouter.productTools()
            + ToolRouter.queryResolverTools() + ToolRouter.imagePromptTools()
            + ToolRouter.translationTools() + ToolRouter.priceReportTools()
        for tool in schemas {
            let function = tool["function"] as? [String: Any]
            let properties = (function?["parameters"] as? [String: Any])?["properties"] as? [String: Any]
            for (name, value) in properties ?? [:] {
                let description = (value as? [String: Any])?["description"] as? String
                guard let description else { continue }
                XCTAssertFalse(description.isEmpty, name)
                XCTAssertFalse(description.contains("{{"), name)
            }
        }
    }

    private func wished(_ wish: String) -> ToolDecision {
        var decision = ToolDecision(route: .chat)
        decision.wish = wish
        return decision
    }

    func testEveryRouterCountsRelativeDaysTheSameWay() {
        let rule = PromptLibrary.text("router_relative_days")
        XCTAssertTrue(rule.contains(#""the day after the day after tomorrow" has two (+3)"#), rule)
        XCTAssertTrue(ToolRouter.systemBlock(now: "Tuesday, 2026-10-27 14:00", context: SendContext(),
                                             transcript: "").contains(rule))
        XCTAssertTrue(Prompt.Router.calendar(tz: "UTC+01:00", now: "2026-10-27 14:00", events: "",
                                             calendars: "", history: "").contains(rule))
        XCTAssertTrue(WeatherDayCheck.hint.contains(rule))
        let conflict = WeatherDayCheck().hint(for: WeatherRequest(place: nil, day: .today, date: "2000-01-01",
                                                                  offset: 3))
        XCTAssertTrue(conflict?.contains(rule) ?? false, conflict ?? "")
    }

    func testEveryBuilderPromptResolvesWithoutLeftovers() {
        let prompts = [
            Prompt.Router.calendar(tz: "UTC+02:00", now: "2026-01-01 09:00", events: "e",
                                   calendars: "c", history: "h", planned: "p"),
            Prompt.Product.finding(),
            Prompt.Price.offers(),
            Prompt.Price.watch(),
            Prompt.Research.webAnswer(),
            Prompt.Research.webAnswer(length: .detailed(items: 3)),
            Prompt.Research.followUpQuery(),
            Prompt.Research.imagePrompt(pictures: 1),
            Prompt.Research.imagePrompt(pictures: 3),
            Prompt.Pictures.director(pictures: 2),
            WishSplitter.system(),
            WishRouting.system("SYS", wish: 1, of: ["a", "b"], offersEdit: true),
            AppointmentReminderCheck.hint,
            PictureChainCheck.hint,
            WeatherDayCheck.hint,
            WeatherDayCheck().hint(for: WeatherRequest(place: nil, day: .today, date: "2000-01-01",
                                                       offset: 3)) ?? "",
            PictureIntentCheck.hint,
            MessageLanguageCheck.hint(for: .english),
            PlaceWishConfirmation.hint,
            ModelTranslation.prompt(for: TranslationJob(text: "Hallo", targetCode: "fr", sourceCode: "de")),
            SystemPrompt.fileProtocol,
            PromptToken.picture,
            PromptToken.context,
            PromptToken.newQuestion,
            FileTextBlocks.fileHead,
            FileTextBlocks.fileEnd,
            FileTextBlocks.pageMarker,
            FileTextBlocks.omittedNotice(2),
            FileTextBlocks.file(name: "x.txt", pages: nil, text: "t", via: .plain, truncated: true),
            ToolRouter.systemBlock(now: "Tuesday, 2026-10-27 14:00", context: SendContext(), transcript: ""),
            WishRouting.answerFocus(wished("a"), among: [wished("a"), wished("b")]),
        ]
        for prompt in prompts {
            XCTAssertFalse(prompt.isEmpty, prompt)
            XCTAssertFalse(prompt.contains("{{"), prompt)
        }
    }
}
