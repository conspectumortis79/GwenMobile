@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TranslationRoutingTests: GwenTestCase {
    func testTheTranslatorIsOfferedAsAToolInTheSameListAsTheRest() throws {
        let names = ToolRouter.tools(attachable: false).compactMap {
            ($0["function"] as? [String: Any])?["name"] as? String
        }
        XCTAssertTrue(names.contains(ToolRouter.translateTool), "\(names)")
        let tool = try XCTUnwrap(ToolRouter.tools(attachable: false).first {
            ((($0["function"] as? [String: Any])?["name"]) as? String) == ToolRouter.translateTool
        })
        let function = try XCTUnwrap(tool["function"] as? [String: Any])
        let description = try XCTUnwrap(function["description"] as? String)
        XCTAssertTrue(description.lowercased().contains("language"), description)
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["target"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(), ["source", "target", "text"])
        let target = try XCTUnwrap(properties["target"] as? [String: Any])
        XCTAssertEqual(target["enum"] as? [String], TranslationLanguages.codes)
    }

    func testTheRouterPolicyMentionsTheTranslator() {
        let block = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.translateTool), block)
    }

    func testTranslationWishesAreAlwaysAskedOfTheRouter() async {
        let unerreichbar = "https://gwenmobile-nicht-vorhanden.invalid/v1"
        let asks = ["Übersetze „Guten Morgen“ ins Französische",
                    "Übersetze den Text auf dem Foto ins Englische",
                    "Bitte auf Türkisch",
                    "Mache das Bild etwas heller"]
        for text in asks {
            for context in [SendContext(), SendContext(attachedImage: true),
                            SendContext(attachedFile: true), SendContext(rememberedImage: true)] {
                let decision = await ToolRouter.decide(RouterAsk(baseURL: unerreichbar, key: "k", model: "m",
                                                                 text: text, context: context, history: [],
                                                                 thinking: .nothing))
                XCTAssertNil(decision, "\(text) / \(context) darf ohne Router nicht lokal entschieden werden")
            }
        }
    }
    func testTheModelsAnswerDecidesTheRouteInsteadOfAWordList() throws {
        let chat = try XCTUnwrap(ToolRouter.decisions(from: payload(ToolRouter.answerTool, "{}")).first)
        XCTAssertEqual(chat.route, .chat, "antwordet das Modell mit chat, bleibt es dabei")

        let ubersetzt = try XCTUnwrap(ToolRouter.decisions(
            from: payload(ToolRouter.translateTool, "{\"text\":\"Hello\",\"target\":\"fr\"}")).first)
        guard case .translate(let job) = ubersetzt.route else {
            return XCTFail("ein translate_text-Aufruf muss ins Übersetzungsgerät, nicht in eine Wortliste")
        }
        XCTAssertEqual(job.text, "Hello")
        XCTAssertEqual(job.targetCode, "fr")
    }

    func testTheTranslateToolIsOnlyOfferedWhenTheDeviceCanReadTheWords() {
        func names(_ tools: [[String: Any]]) -> [String] {
            tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        }
        let erlaubt = names(ToolRouter.tools(attachable: true, translatesOnDevice: true))
        let verboten = names(ToolRouter.tools(attachable: true, translatesOnDevice: false))
        XCTAssertTrue(erlaubt.contains(ToolRouter.translateTool), "\(erlaubt)")
        XCTAssertFalse(verboten.contains(ToolRouter.translateTool), "\(verboten)")
        XCTAssertEqual(verboten.count, erlaubt.count - 1)
        XCTAssertEqual(erlaubt, names(ToolRouter.tools(attachable: true)), "Standard lässt das Gerät übersetzen")
    }

    func testTheRouterPolicyForbidsTheTranslatorWhileAnAttachmentCarriesTheWords() {
        let angehängt = ToolRouter.systemBlock(now: "heute", context: SendContext(attachedImage: true),
                                              transcript: "")
        XCTAssertTrue(angehängt.contains("translate them yourself and answer in chat"), angehängt)
        XCTAssertFalse(angehängt.contains("Use translate_text whenever"), angehängt)
        let nurWorte = ToolRouter.systemBlock(now: "heute", context: SendContext(rememberedImage: true),
                                             transcript: "")
        XCTAssertTrue(nurWorte.contains("Use translate_text whenever"), nurWorte)
        XCTAssertTrue(angehängt.contains("is \(ToolRouter.editTool)"), angehängt)
        XCTAssertTrue(angehängt.contains("first and \(ToolRouter.editTool) second"), angehängt)
        XCTAssertFalse(angehängt.contains("never \(ToolRouter.editTool)"), angehängt)
        XCTAssertTrue(angehängt.contains("Never \(ToolRouter.findTool) for it"), angehängt)
    }

    func testATranslationCallBecomesATranslateRoute() throws {
        let data = payload(ToolRouter.translateTool,
                           #"{"text":"Hello there","target":"fr","source":"en"}"#)
        let decision = try XCTUnwrap(ToolRouter.decisions(from: data).first)
        guard case .translate(let job) = decision.route else {
            return XCTFail("andere Route: \(decision.route)")
        }
        XCTAssertEqual(job.text, "Hello there")
        XCTAssertEqual(job.targetCode, "fr")
        XCTAssertEqual(job.sourceCode, "en")
        XCTAssertFalse(job.fromChat)
    }

    func testAnEmptyTextFromTheRouterIsFilledWithTheLastAnswer() throws {
        let history = [ChatMessage(role: .user, text: "Was ist ein Regal?"),
                       ChatMessage(role: .assistant, text: "Ein Regal ist ein Möbelstück."),
                       ChatMessage(role: .user, text: "Übersetze das")]
        let data = payload(ToolRouter.translateTool, #"{"target":"fr"}"#)
        let decision = try XCTUnwrap(ToolRouter.decisions(from: data).first?.withChatText(excluding: history.last!.text,
                                                                                  history: history))
        guard case .translate(let job) = decision.route else {
            return XCTFail("andere Route: \(decision.route)")
        }
        XCTAssertEqual(job.text, "Ein Regal ist ein Möbelstück.")
        XCTAssertTrue(job.fromChat)
    }

    func testAnUnknownTargetLanguageStillLeavesTheChatRouteUntouched() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: payload(ToolRouter.answerTool, "{}")).first)
        XCTAssertEqual(decision.route, .chat)
    }

    func testAnUntranslatableJobKeepsItsOwnRouteAndReportsNoText() {
        let job = TranslationJob(text: "", targetCode: "fr")
        XCTAssertTrue(job.isEmpty)
        XCTAssertEqual(job.withText("Ersatz", fromChat: true).text, "Ersatz")
    }

    @MainActor
    func testAChatTranslationTakesTheFreshChainAnswerInsteadOfTheOldHistory() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Die alte Antwort"))
        carry.add(AnswerPiece(text: "Die neue Zusammenfassung"))
        let carried = TranslationJob(text: "Die alte Antwort", targetCode: "fr", fromChat: true)
        XCTAssertEqual(carried.resolved(with: carry).text, "Die neue Zusammenfassung")
        let explicit = TranslationJob(text: "Ein eigener Satz", targetCode: "fr")
        XCTAssertEqual(explicit.resolved(with: carry).text, "Ein eigener Satz")
    }

    @MainActor
    func testAnEmptyTranslationFallsBackToTheChainAndKeepsItsOldTextWithoutOne() {
        let carry = AnswerCarry()
        let empty = TranslationJob(text: "", targetCode: "fr")
        XCTAssertEqual(empty.resolved(with: carry).text, "")
        carry.add(AnswerPiece(text: "Der frische Text"))
        XCTAssertEqual(empty.resolved(with: carry).text, "Der frische Text")
        XCTAssertTrue(empty.resolved(with: carry).fromChat)
    }
}
