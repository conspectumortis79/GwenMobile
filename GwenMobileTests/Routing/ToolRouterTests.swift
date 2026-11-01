@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ToolRouterTests: XCTestCase {
    func testAPictureWithoutASingleWordNeverReachesTheToolChoice() {
        XCTAssertTrue(ToolRouter.carriesOnlyPictures(text: "", pictures: 1))
        XCTAssertTrue(ToolRouter.carriesOnlyPictures(text: "  \n ", pictures: 3))
    }

    func testWordsOrNoPictureStillLeaveTheToolRouterInCharge() {
        XCTAssertFalse(ToolRouter.carriesOnlyPictures(text: "mach ein bild", pictures: 1))
        XCTAssertFalse(ToolRouter.carriesOnlyPictures(text: "", pictures: 0))
    }

    func testEveryRoutingRequestPinsTheTemperature() throws {
        let baseURL = "https://example.test/v1"
        let requests = [
            try ToolRouter.request(baseURL: baseURL, key: "k", model: "m", text: "Hallo",
                                   system: "system", attachable: false, thinking: .nothing),
            try ToolRouter.scanReminderRequest(baseURL: baseURL, key: "k", model: "m", text: "Hallo",
                                               context: SendContext(), history: [], document: "",
                                               thinking: .nothing),
            try WishSplitter.request(baseURL: baseURL, key: "k", model: "m", text: "Hallo",
                                     thinking: .nothing),
            try ToolRouter.sourceFilterRequest(baseURL: baseURL, key: "k", model: "m", question: "Frage",
                                               hits: [], thinking: .nothing),
        ]
        for request in requests {
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(object["temperature"])
        }
    }

    func testTheStatusToolRoutesWithoutArguments() {
        XCTAssertEqual(ToolRouter.map(name: ToolRouter.appStatusTool, arguments: "{}")?.route, .appStatus)
        XCTAssertEqual(ToolRouter.map(name: ToolRouter.appStatusTool, arguments: "")?.route, .appStatus)
    }

    func testTheActionToolsCarryTheArgumentsTheFlowsNeed() throws {
        let withPicture = ToolRouter.tools(attachable: true)
        func required(_ name: String) -> [String] {
            let tool = withPicture.first { ($0["function"] as? [String: Any])?["name"] as? String == name }
            let parameters = (tool?["function"] as? [String: Any])?["parameters"] as? [String: Any]
            return parameters?["required"] as? [String] ?? []
        }
        XCTAssertEqual(required(ToolRouter.editTool), ["instruction", "monochrome"])
        XCTAssertEqual(required(ToolRouter.monochromeTool), [])
        XCTAssertEqual(required(ToolRouter.createTool), ["prompt"])
        XCTAssertEqual(required(ToolRouter.searchTool), ["query"])
        XCTAssertEqual(required(ToolRouter.findTool), ["query"])
        XCTAssertEqual(required(ToolRouter.answerTool), [])
    }

    func testThePictureToolAlsoDrawsDiagrams() throws {
        let create = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.createTool
        }
        let description = try XCTUnwrap((create?["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains("flowchart"), description)
        XCTAssertTrue(description.contains("diagram"), description)
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains("flowchart"), block)
        XCTAssertTrue(block.contains("drawn graphic"), block)
    }

    func testTheFoundPictureToolIsAlwaysOfferedAndTheEditorOnlyWithAPicture() {
        XCTAssertEqual(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).count, 26)
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.videoTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.findTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.priceTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.watchPriceTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.briefingTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.scanTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.appStatusTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.editTool))
        XCTAssertFalse(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.editTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.monochromeTool))
        XCTAssertFalse(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.monochromeTool))
    }

    func testThePictureReportIsAContractOfItsOwnAndNeverAChoiceOfTheRouter() throws {
        XCTAssertFalse(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.productTool),
                       "der befund kommt aus dem bildaufruf, er darf keine route sein")
        let calls = ToolRouter.toolCalls(from: call(ToolRouter.productTool, #"{"product":"Jura ENA 4"}"#))
        XCTAssertEqual(calls.map(\.name), [ToolRouter.productTool])
        XCTAssertTrue(ToolRouter.toolCalls(from: Data("{}".utf8)).isEmpty)
        XCTAssertTrue(ToolRouter.toolCalls(from: Data("not json".utf8)).isEmpty)
    }

    func testAnswerInChatIsNamedAsUnableToShowAPicture() throws {
        let answer = try XCTUnwrap(ToolRouter.tools(attachable: true).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.answerTool
        })
        let description = try XCTUnwrap((answer["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains("never changes a picture"), description)
        XCTAssertTrue(description.contains(ToolRouter.editTool),
                      "ohne den Verweis auf edit_picture bleibt ein Änderungswunsch ohne Bild hängen")
    }

    func testAProseAnswerIsAskedAgainAndTheToolCallThenWins() async {
        let calls = LockedValue(0)
        let decision = await ToolRouter.plan(asking: {
            let attempt = calls.mutate { stored in stored += 1; return stored }
            return attempt == 1 ? RouterPayloads.prose("Ich kann leider keine Bilder bearbeiten.")
                : RouterPayloads.tool(ToolRouter.findTool, "{\"query\":\"unfall a3\"}")
        }).first
        XCTAssertEqual(calls.current, 2, "der erste Prosa-Ausbruch darf nicht als chat-Lesart enden")
        XCTAssertEqual(decision?.route, .pictureSearch(query: "unfall a3"))
    }

    func testTwoProseAnswersStillEndWithoutAnInventedDecision() async {
        let calls = LockedValue(0)
        let decision = await ToolRouter.plan(asking: {
            calls.mutate { stored in stored += 1 }
            return RouterPayloads.prose("Nur Text, kein Werkzeugbericht.")
        }).first
        XCTAssertNil(decision)
        XCTAssertEqual(calls.current, ToolRouter.decisionAttempts)
    }

    func testATransportFailureIsNeverAskedAgain() async {
        let calls = LockedValue(0)
        let decision = await ToolRouter.plan(asking: {
            calls.mutate { stored in stored += 1 }
            throw APIError(message: "HTTP 503")
        }).first
        XCTAssertNil(decision)
        XCTAssertEqual(calls.current, 1, "ein Transportfehler ist kein Grund für eine zweite Rechnung")
    }

    func testAnswerShapeNamesWhatTheProviderGaveBack() {
        let text = "zwölf zeichen text hier"
        XCTAssertEqual(ToolRouter.answerShape(of: RouterPayloads.prose(text)),
                       "ende=stop text=\(text.count)")
        XCTAssertEqual(ToolRouter.answerShape(of: RouterPayloads.tool(ToolRouter.answerTool, "{}")),
                       "ende=- text=0")
    }

    func testThePriceToolNeedsOnlyTheNamesAndOffersLandAndNearby() throws {
        let price = try XCTUnwrap(ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.priceTool
        })
        let parameters = (price["function"] as? [String: Any])?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["required"] as? [String], ["terms"],
                       "ein Pflichtfeld für das Land wurde gemessen: 4/10 statt 11/12 und zwei Sätze wanderten "
                       + "zu find_nearby_place")
        let properties = try XCTUnwrap(parameters?["properties"] as? [String: Any])
        let terms = try XCTUnwrap(properties["terms"] as? [String: Any])
        XCTAssertEqual(terms["type"] as? String, "array", "ein Produkt ist mehrdeutig, ein einzelnes Wort nie")
        XCTAssertEqual((properties["country"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual((properties["nearby"] as? [String: Any])?["type"] as? String, "boolean")
    }

    func testTheCountryIsCopiedFromTheUserAndNeverWorkedOut() throws {
        let price = try XCTUnwrap(ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.priceTool
        })
        let parameters = try XCTUnwrap((price["function"] as? [String: Any])?["parameters"]
                                       as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let country = try XCTUnwrap((properties["country"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(country.contains("copied out of the user's own words"), country)
        XCTAssertTrue(country.contains("Never a country you worked out"), country)
        XCTAssertTrue(country.contains("read off a shop name"), country)
        XCTAssertTrue(country.contains("has to be answered here"), country)
        XCTAssertFalse(country.contains("e.g."), "beispiel-länder werden kopiert, wo keines genannt war")
        let policy = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(policy.contains("Copy into country every country the user's own words hold"), policy)
        XCTAssertTrue(policy.contains("a country they named must not be dropped"), policy)
    }

    func testAWhoOrWhatQuestionNeverWantsPhotographs() throws {
        let find = try XCTUnwrap(ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.findTool
        })
        let description = try XCTUnwrap((find["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains("it never answers who or what"), description)
        XCTAssertTrue(description.contains("who is the director of Vertigo"), description)
        let policy = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(policy.contains("a question that only asks who or what"), policy)
        XCTAssertTrue(description.contains(ToolRouter.answerTool), description)
    }

    func testAPriceWishMapsOntoItsOwnRouteAndEveryNameSurvives() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(
            ToolRouter.priceTool,
            "{\"terms\":[\"Jura ENA 4\",\"Jura ENA 4\",\"Kaffeevollautomat\",\"Jura\",\"Vollautomat\"]}")).first)
        XCTAssertEqual(decision.route, .priceSearch(terms: ["Jura ENA 4", "Kaffeevollautomat", "Jura",
                                                            "Vollautomat"],
                                                   country: nil, nearby: false))
    }

    func testThePriceToolIsBoundToAPurchaseAndNotToTheWordForPrice() throws {
        let price = try XCTUnwrap(ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.priceTool
        })
        let description = try XCTUnwrap((price["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains("only when the user wants to buy"), description)
        XCTAssertTrue(description.contains("prize money"), description)
        XCTAssertTrue(description.contains("awards, medals"), description)
        XCTAssertTrue(description.contains("jackpot"), description)
        XCTAssertTrue(description.contains("idiom"), description)
        let policy = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(policy.contains("Use compare_prices only for a purchase"), policy)
        XCTAssertTrue(policy.contains("The word for price alone never decides this"), policy)
        XCTAssertTrue(policy.contains("never \(ToolRouter.priceTool)"), policy)
    }

    func testTheRouterRequestCarriesThePictureTheDecisionIsMadeFrom() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let plain = try ToolRouter.request(baseURL: "https://api.test/v1", key: "k", model: "m",
                                          text: "frage", system: "s", attachable: false,
                                          thinking: .nothing)
        let plainMessages = try XCTUnwrap((try XCTUnwrap(JSONSerialization.jsonObject(
            with: plain.httpBody ?? Data()) as? [String: Any]))["messages"] as? [[String: Any]])
        XCTAssertTrue(plainMessages.last?["content"] is String, "ohne Bild bleibt es Text")

        let seen = try ToolRouter.request(baseURL: "https://api.test/v1", key: "k", model: "vision",
                                         text: "frage", system: "s", attachable: true, picture: jpeg,
                                         thinking: .nothing)
        let seenMessages = try XCTUnwrap((try XCTUnwrap(JSONSerialization.jsonObject(
            with: seen.httpBody ?? Data()) as? [String: Any]))["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(seenMessages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first?["text"] as? String, "frage")
        XCTAssertTrue(parts[1]["image_url"] != nil,
                      "nur wenn das Bild mitfährt, kann der Router selbst darin lesen")
    }

    func testTheCheapestThingWishIsAnchoredAsAPurchaseWithoutAPicture() {
        let policy = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(policy.contains("is such a wish even with no picture in play"), policy)
    }

    func testTheBuyWishStaysApartFromQuestionsAboutThePictureInBothStates() {
        let attached = ToolRouter.systemBlock(now: "x", context: SendContext(attachedImage: true),
                                             transcript: "")
        XCTAssertTrue(attached.contains("a question about it is answer_in_chat"), attached)
        XCTAssertTrue(attached.contains("A wish to buy what the picture shows"), attached)
        XCTAssertTrue(attached.contains(ToolRouter.priceTool), attached)
        let remembered = ToolRouter.systemBlock(now: "x", context: SendContext(rememberedImage: true),
                                               transcript: "")
        XCTAssertTrue(remembered.contains("A wish to buy the thing on that picture"), remembered)
        XCTAssertFalse(remembered.contains("## IMAGE FINDING"),
                       "der Router sieht das Bild selbst, ein Textauszug wird ihm nicht vorweggelesen")
    }

    func testANamedCountryAndALocalWishTravelOnTheSameRoute() throws {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.priceTool,
                     "{\"terms\":[\"Ekspres do kawy\"],\"country\":\"PL\"}")).first?.route,
                       .priceSearch(terms: ["Ekspres do kawy"], country: "PL", nearby: false))
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.priceTool,
                     "{\"terms\":[\"Jura ENA 4\"],\"nearby\":true}")).first?.route,
                       .priceSearch(terms: ["Jura ENA 4"], country: nil, nearby: true))
    }

    func testAnEmptyTermListNeverStartsAComparison() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.priceTool, "{\"terms\":[]}")).first?.route, .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.priceTool, "{}")).first?.route, .chat)
    }

    func testTheCodeToolCarriesOnlyTheLanguageAndNamesItselfInThePictureDescription() throws {
        let tools = ToolRouter.tools(attachable: false)
        let code = try XCTUnwrap(tools.first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.codeTool
        })
        let parameters = (code["function"] as? [String: Any])?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["required"] as? [String], ["language"])
        let properties = parameters?["properties"] as? [String: Any]
        XCTAssertEqual((properties?["language"] as? [String: Any])?["enum"] as? [String],
                       CodeLanguage.toolValues)
        let picture = try XCTUnwrap(tools.first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.createTool
        })
        let description = try XCTUnwrap((picture["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains(ToolRouter.codeTool),
                      "ohne den Verweis auf write_code bleibt 'Tetris als HTML-Datei' beim Bildpfad")
    }

    func testACodeWishMapsOntoTheCodeRouteWithItsLanguage() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.codeTool,
                                                     "{\"language\":\"html\"}")).first?.route,
                       .code(language: .html))
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.codeTool,
                                                     "{\"language\":\"Python\"}")).first?.route,
                       .code(language: .python))
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.codeTool, "{}")).first?.route,
                       .code(language: .text))
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.codeTool,
                                                     "{\"language\":\"webpage\"}")).first?.route,
                       .code(language: .html))
    }

    func testSystemBlockKeepsAFileOfCodeAwayFromThePictureTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.codeTool), block)
        XCTAssertTrue(block.contains("never a picture wish"), block)
        XCTAssertTrue(block.contains("HTML"), block)
    }

    func testTheCalendarToolCarriesTheSameFieldsAsThePlanJson() {
        let calendar = ToolRouter.tools(attachable: true).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.calendarTool
        }
        let parameters = (calendar?["function"] as? [String: Any])?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["required"] as? [String], ["action"])
        let properties = parameters?["properties"] as? [String: Any]
        XCTAssertEqual((properties?["action"] as? [String: Any])?["enum"] as? [String],
                       ["create", "update", "delete", "none"])
        XCTAssertNotNil(properties?["alerts"])
    }

    func testEveryToolCallMapsOntoTheExistingRoute() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.answerTool, "{}")).first?.route, .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.codeTool,
                                                     "{\"language\":\"css\"}")).first?.route,
                       .code(language: .css))
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.editTool,
                                                     "{\"instruction\":\"heller\"}")).first?.pictureInstruction, "heller")
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.createTool,
                                                      "{\"prompt\":\"Stadt bei Nacht\"}")).first?.picturePrompt,
                       "Stadt bei Nacht")
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.calendarTool,
                                                     "{\"action\":\"create\",\"title\":\"Zahnarzt\"}")).first?.route,
                       .calendar)
    }

    func testSearchQueryBecomesAChatRouteWithTheResearchWishAttached() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.searchTool, "{\"query\":\"Einwohner Deutschland 2025\"}")).first)
        XCTAssertEqual(decision.route, .chat)
        XCTAssertEqual(decision.searchQuery, "Einwohner Deutschland 2025")
        XCTAssertFalse(decision.detailWish)
    }

    func testTheRouterDecidesWhetherAQuestionWantsMoreDetailFromTheWeb() throws {
        let detailed = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.searchTool,
                       "{\"query\":\"Nachrichten Berlin\",\"detail\":true}")).first)
        XCTAssertTrue(detailed.detailWish)
        let plain = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.searchTool, "{\"query\":\"Nachrichten Berlin\"}")).first)
        XCTAssertFalse(plain.detailWish)
    }

    func testTheSearchToolOffersTheDetailWishAndStillRequiresTheQuery() throws {
        let parameters = try toolParameters(ToolRouter.searchTool)
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["detail"])
        XCTAssertEqual(parameters["required"] as? [String], ["query"])
    }

    func testNamelessFragmentsAreSkippedAndTheRealCallWins() throws {
        let data = payload([["id": "a", "function": ["arguments": "{title"]],
                            ["id": "b", "function": ["name": "create_picture",
                                                     "arguments": "{\"prompt\":\"Berg\"}"]]])
        let decision = try XCTUnwrap(ToolRouter.decisions(from: data).first)
        XCTAssertEqual(decision.route, .imageCreate)
    }

    func testPlainAnswerWithoutToolCallStaysUnhandled() {
        XCTAssertNil(ToolRouter.decisions(from: payload([], "Paris")).first)
        XCTAssertNil(ToolRouter.decisions(from: Data("{".utf8)).first)
    }

    func testCalendarActionNoneFallsBackToChat() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.calendarTool, "{\"action\":\"none\"}")).first
        XCTAssertEqual(decision?.route, .chat)
        XCTAssertNil(decision?.calendarAction)
    }

    func testTheToolRequestBodyCarriesEveryFieldTheProviderNeeds() throws {
        let body = ToolRouter.toolRequestBody(model: "qwen3.8-flash", maxTokens: 220, stream: false,
                                             messages: [["role": "user", "content": "frage"]],
                                             tools: [["type": "function"]])
        XCTAssertEqual(body["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(body["max_tokens"] as? Int, 220)
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertNil(body["tool_choice"])
        XCTAssertNotNil(body["messages"] as? [[String: Any]])
        XCTAssertNotNil(body["tools"] as? [[String: Any]])
    }

    func testTheSendTraceNamesEverySlotOfTheDecision() {
        L.apply(.de)
        let decision = ToolDecision(route: .calendar, searchQuery: "abfrage",
                                    calendarPlan: QwenAPI.CalendarPlan(action: .create))
        let trace = ChatView.sendTrace(decision: decision)
        XCTAssertTrue(trace.contains("suchtext=abfrage"), trace)
        XCTAssertTrue(trace.contains("termin=create"), trace)
        XCTAssertEqual(ChatView.describeAction(nil), "-")
        XCTAssertEqual(ChatView.describeAction(QwenAPI.CalendarPlan.Action.delete), "delete")
    }

    func testBrokenArgumentsStillCarryTheChosenRoute() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.searchTool, "{query")).first?.route, .chat)
        XCTAssertNil(ToolRouter.decisions(from: call(ToolRouter.searchTool, "{query")).first?.searchQuery)
    }

    func testSystemBlockNamesDatePictureStateAndTranscript() {
        let attached = ToolRouter.systemBlock(now: "Sonntag, 2026-09-13",
                                              context: SendContext(attachedImage: true),
                                              transcript: "user: vorige Frage")
        XCTAssertTrue(attached.contains("Current date: Sonntag, 2026-09-13"))
        XCTAssertTrue(attached.contains("attached a new picture"))
        XCTAssertTrue(attached.contains("user: vorige Frage"))
        XCTAssertTrue(attached.contains("question about it is answer_in_chat"))
        XCTAssertTrue(attached.contains("black and white, another background, brighter - is edit_picture"), attached)
        XCTAssertTrue(attached.contains("answer_in_chat first and edit_picture second"), attached)
        XCTAssertTrue(attached.contains("Never find_pictures for it"), attached)
        XCTAssertTrue(attached.contains("already on screen"))
        let remembered = ToolRouter.systemBlock(now: "x", context: SendContext(rememberedImage: true),
                                                transcript: "")
        XCTAssertTrue(remembered.contains("still on screen"))
        XCTAssertFalse(remembered.contains("Recent conversation"))
        let plain = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertFalse(plain.contains("attached a new picture"))
        XCTAssertFalse(plain.contains("still on screen"))
    }

    func testRequestSendsToolsAndLeavesTheChoiceToTheModel() throws {
        let req = try ToolRouter.request(baseURL: "https://api.test/v1", key: "sk-x", model: "m",
                                         text: "mach ein bild", system: "sys", attachable: false,
                                         thinking: .suppressing(.dashScope))
        let body = try XCTUnwrap(jsonBody(of: req))
        XCTAssertNil(body["tool_choice"])
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        XCTAssertNotNil(body["tools"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "sys")
        XCTAssertEqual(messages.last?["content"] as? String, "mach ein bild")
    }

    func testTheCompactSchemasStaySmallerThanTheFullOnes() throws {
        let full = try JSONSerialization.data(withJSONObject: ToolRouter.tools(attachable: false,
                                                                              compact: false))
        let compact = try JSONSerialization.data(withJSONObject: ToolRouter.tools(attachable: false,
                                                                                  compact: true))
        XCTAssertLessThan(compact.count, full.count)
    }

    func testTwoCalendarPlansWithDifferentDetailsAreNeverEqual() throws {
        let dentist = try XCTUnwrap(ToolRouter.map(name: ToolRouter.calendarTool,
                                                   arguments: #"{"action":"create","title":"Zahnarzt","start":"2026-09-14 14:00"}"#))
        let barber = try XCTUnwrap(ToolRouter.map(name: ToolRouter.calendarTool,
                                                  arguments: #"{"action":"create","title":"Friseur","start":"2026-09-14 14:00"}"#))
        XCTAssertEqual(dentist.calendarAction, barber.calendarAction)
        XCTAssertNotEqual(dentist, barber)
    }
}

private enum RouterPayloads {
    static func prose(_ text: String) -> Data {
        let body: [String: Any] = ["choices": [["message": ["content": text, "tool_calls": []],
                                                "finish_reason": "stop"]],
                                   "usage": ["completion_tokens": 40]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    static func tool(_ name: String, _ arguments: String) -> Data {
        let body: [String: Any] = ["choices": [["message": ["tool_calls": [["id": "c1", "type": "function",
                                                                            "function": ["name": name,
                                                                                         "arguments":
                                                                                                arguments]]]]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
