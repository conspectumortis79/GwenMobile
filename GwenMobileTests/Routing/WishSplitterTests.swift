@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WishSplitterTests: GwenTestCase {
    func testTheWishListIsReadOutOfTheAnswerInItsOrder() {
        let answer = "Hier: {\"wishes\": [\"Wer ist Natalie Portman?\", \"  \", \"Zeig mir Bilder von ihr\"]}"
        XCTAssertEqual(WishSplitter.parse(answer)?.parts.map(\.text),
                       ["Wer ist Natalie Portman?", "Zeig mir Bilder von ihr"],
                       "leere Einträge fallen weg, die Reihenfolge des Nutzers bleibt")
    }

    func testACutOffListKeepsEveryWishThatWasCompletelyWritten() {
        let cut = "{\"wishes\": [\"Termin um 8 Uhr\", \"Termin um 9 \\\"frueh\\\" Uhr\" , \"Male eine Ka"
        XCTAssertEqual(WishSplitter.parse(cut)?.parts.map(\.text),
                       ["Termin um 8 Uhr", "Termin um 9 \"frueh\" Uhr"],
                       "ein abgeschnittener letzter Eintrag fällt weg, die fertigen bleiben")
        XCTAssertEqual(TruncatedStringList.strings(under: "wishes", in: "{\"wishes\": [\"a\", \"b\"], \"x\": \"c\"}"),
                       ["a", "b"], "hinter der geschlossenen Liste wird nichts mehr gelesen")
        XCTAssertEqual(TruncatedStringList.strings(under: "wishes", in: "keine liste"), [])
    }

    func testTheSplitBudgetCarriesFarMoreThanFourWishes() {
        XCTAssertGreaterThanOrEqual(WishSplitter.maxTokens, 4000)
    }

    func testAnAnsweringStepIsToldWhichWishIsItsOwn() {
        var chat = ToolDecision(route: .chat)
        chat.wish = "Was für ein Gerät ist auf dem Foto?"
        var price = ToolDecision(route: .priceSearch(terms: ["Jura"], country: nil, nearby: false))
        price.wish = "Such mir das günstigste Angebot mit dieser EAN."
        let focus = WishRouting.answerFocus(chat, among: [chat, price])
        XCTAssertTrue(focus.contains("1. Was für ein Gerät ist auf dem Foto?\n"
                                     + "2. Such mir das günstigste Angebot mit dieser EAN."), focus)
        XCTAssertTrue(focus.contains("This step answers only wish 1: Was für ein Gerät ist auf dem Foto?"), focus)
        XCTAssertTrue(focus.contains("never ask for a web search because of them"), focus)
        XCTAssertTrue(WishRouting.answerFocus(price, among: [chat, price])
            .contains("This step answers only wish 2: Such mir das günstigste Angebot mit dieser EAN."))
        XCTAssertEqual(WishRouting.answerFocus(ToolDecision(route: .chat), among: [chat, price]), "")
        XCTAssertEqual(WishRouting.answerFocus(chat, among: [chat]), "")
        var twice = price
        twice.wish = chat.wish
        XCTAssertEqual(WishRouting.answerFocus(chat, among: [chat, twice]), "", "derselbe Wunsch zweimal ist einer")
    }

    func testTheSplitterMarksARequestedVideoAndItsDuration() {
        let answer = #"{"wishes":["Erstelle ein 10-Sekunden-Video von einem Paar","Was ist ein Video?"],"independent":[],"places":["",""],"lists":["",""],"videos":[1],"video_seconds":["10",""],"video_ratios":["9:16",""]}"#
        let parts = try? XCTUnwrap(WishSplitter.parse(answer)?.parts)
        XCTAssertEqual(parts?.map(\.isVideo), [true, false])
        XCTAssertEqual(parts?.first?.videoSeconds, 10)
        XCTAssertEqual(parts?.first?.videoRatio, .portrait)
        XCTAssertNil(parts?.last?.videoSeconds)
    }

    func testAVideoWishReplacesAChatOrPictureDecisionButNotOtherTools() {
        let video = WishPart(text: "Erstelle ein 10-Sekunden-Video von einem Paar", independent: true,
                             isVideo: true, videoSeconds: 10, videoRatio: .portrait)
        let plain = WishPart(text: "Wer ist Natalie Portman?", independent: true)
        let calendar = ToolDecision(route: .calendar)
        let applied = WishRouting.applyingVideoWishes(
            [ToolDecision(route: .chat), ToolDecision(route: .imageCreate, picturePrompt: "Paar"),
             calendar, ToolDecision(route: .videoCreate(VideoRequest(prompt: "alt")))],
            parts: [video, plain, plain, video])
        guard case .videoCreate(let request) = applied[0].route else {
            return XCTFail("route was \(applied[0].route)")
        }
        XCTAssertEqual(request.prompt, video.text)
        XCTAssertEqual(request.clampedDuration, 10)
        XCTAssertEqual(request.ratio, .portrait)
        XCTAssertEqual(applied[1].stepKind, .create)
        XCTAssertEqual(applied[2].stepKind, .calendar)
        XCTAssertEqual(applied[3].route, .videoCreate(VideoRequest(prompt: "alt")))
        XCTAssertEqual(WishRouting.applyingVideoWishes([ToolDecision(route: .chat)], parts: nil).count, 1)
        XCTAssertEqual(WishRouting.applyingVideoWishes([ToolDecision(route: .chat)], parts: [video]).count, 1)
    }

    func testAnUnreadableOrEmptyListIsNoList() {
        XCTAssertNil(WishSplitter.parse(nil))
        XCTAssertNil(WishSplitter.parse("keine Ahnung"))
        XCTAssertNil(WishSplitter.parse("{\"wishes\": []}"))
        XCTAssertNil(WishSplitter.parse("{\"wishes\": [\" \"]}"))
    }

    func testTheSplitterIsToldHowToCountRepeatsAndSeveralThingsOfOneKind() {
        let system = WishSplitter.system()
        XCTAssertTrue(system.contains("two appointments are two wishes"), system)
        XCTAssertTrue(system.contains("One wish said twice, also in other words, stays one wish"), system)
        XCTAssertTrue(system.contains("in the order the user wrote them"), system)
        XCTAssertTrue(system.contains("A question and the request to find out exactly that answer are one wish"),
                      system)
        XCTAssertTrue(WishRouting.system("SYS", wish: 0, of: ["a"], offersEdit: false)
            .contains("this wish alone decides the tool"))
        XCTAssertTrue(system.contains("A comparison is one wish"), system)
        XCTAssertTrue(system.contains("Never turn a comparison of performance, quality, features, speed, "
                                      + "benchmarks or specifications into price wishes"), system)
        XCTAssertTrue(system.contains("words for prices, costs or buying appear only when the user used them"),
                      system)
        XCTAssertTrue(system.contains("asks for the same thing on several days or for several dates is one wish"),
                      system)
        XCTAssertTrue(system.contains("A wish that only asks for more about the same place or thing"), system)
        XCTAssertTrue(system.contains("{\"wishes\""), system)
    }

    func testAPerWishRouterSeesTheOtherWishesAsContext() {
        let system = WishRouting.system("SYS", wish: 1,
                                        of: ["Wo ist der nächste Kaufland-Markt?",
                                             "Zeig mir bitte auch die Öffnungszeiten."],
                                        offersEdit: false)
        XCTAssertTrue(system.contains("1. Wo ist der nächste Kaufland-Markt?"), system)
        XCTAssertTrue(system.contains("2. Zeig mir bitte auch die Öffnungszeiten."), system)
        XCTAssertTrue(system.contains("You answer only wish 2"), system)
        XCTAssertFalse(system.contains("{{"), system)
    }

    func testTheSplitRequestAsksWithoutToolsAndWithItsOwnBudget() throws {
        let request = try WishSplitter.request(baseURL: "https://q.test/v1", key: "k", model: "m",
                                               text: "Male eine Katze und einen Hund",
                                               thinking: .nothing)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["tools"])
        XCTAssertEqual(object["max_tokens"] as? Int, WishSplitter.maxTokens)
        XCTAssertEqual(object["stream"] as? Bool, false)
    }

    func testTheSplitterDecidesHowManyStepsThereAre() {
        let chat = ToolDecision(route: .chat)
        let create = ToolDecision(route: .imageCreate, picturePrompt: "Mona Lisa")
        let again = ToolDecision(route: .imageCreate, picturePrompt: "Mona Lisa als Farbbild")
        XCTAssertEqual(WishRouting.chosen(wishes: ["ein Wunsch"], whole: [create, again], routed: []),
                       [create], "ein einziger Wunsch ist genau eine Stufe, auch wenn der Router zwei nennt")
        XCTAssertEqual(WishRouting.chosen(wishes: nil, whole: [chat, create], routed: []), [chat, create],
                       "ohne lesbare Zerlegung gilt die erste Entscheidung")
        XCTAssertEqual(WishRouting.chosen(wishes: ["a", "b"], whole: [chat], routed: [create, again]),
                       [create, again])
        XCTAssertEqual(WishRouting.chosen(wishes: ["a", "b"], whole: [chat], routed: []), [chat],
                       "scheitert jede Einzelentscheidung, bleibt die erste Entscheidung")
    }

    func testSeveralMemoryFactsFromOneWishStayAll() {
        let bananas = ToolDecision(route: .memory(MemoryRequest(action: .suggest, text: "Ich mag Bananen")))
        let allergy = ToolDecision(route: .memory(MemoryRequest(action: .suggest, text: "Ich bin allergisch auf Äpfel")))
        XCTAssertEqual(WishRouting.chosen(wishes: ["Merke dir meine Vorlieben"],
                                          whole: [bananas, allergy], routed: []),
                       [bananas, allergy])
    }

    func testSeveralAppointmentsFromOneWishStayAll() throws {
        let eight = try XCTUnwrap(ToolRouter.map(name: ToolRouter.calendarTool,
                                                 arguments: #"{"action":"create","start":"2026-11-01 08:00"}"#))
        let nine = try XCTUnwrap(ToolRouter.map(name: ToolRouter.calendarTool,
                                                arguments: #"{"action":"create","start":"2026-11-01 09:00"}"#))
        let chosen = WishRouting.chosen(wishes: ["Trag Termine morgen um 8 und 9 Uhr ein"],
                                        whole: [eight, nine], routed: [])
        XCTAssertEqual(chosen.map(\.stepKind), [.calendar, .calendar])
        XCTAssertEqual(SendPlan.forming(chosen).actions.count, 2)
    }

    func testEveryWishIsRoutedOnItsOwnAndKeepsItsPlace() async {
        let wishes = ["Erstelle einen Termin morgen um 11 Uhr", "Stört", "Male eine Katze"]
        let calendar = payload(ToolRouter.calendarTool, #"{"action":"create","start":"2026-09-30 11:00"}"#)
        let cat = payload(ToolRouter.createTool, #"{"prompt":"eine Katze"}"#)
        let routed = await WishRouting.routed(wishes) { index, _, _ in
            switch index {
            case 0: return calendar
            case 2: return cat
            default: throw URLError(.timedOut)
            }
        }
        XCTAssertEqual(routed.map(\.stepKind), [.calendar, .chat, .create],
                       "ein Wunsch ohne Werkzeugaufruf wird wie jede Nachricht ohne Aufruf im Chat beantwortet")
        XCTAssertEqual(routed.map(\.wish), wishes)
    }

    func testASingleWishNeedsNoSecondRound() async {
        let routed = await WishRouting.routed(["nur einer"]) { _, _, _ in
            XCTFail("ein einziger Wunsch wird nicht noch einmal geroutet")
            return Data()
        }
        XCTAssertTrue(routed.isEmpty)
    }

    func testOnlyAPictureOrAnswerWishBehindAPictureIsAskedAgainWithTheEditTool() async {
        let wishes = ["Male einen roten Ball", "Mach das neue Bild schwarz-weiß", "Wo ist der nächste REWE?"]
        let ball = payload(ToolRouter.createTool, #"{"prompt":"roter Ball"}"#)
        let blind = payload(ToolRouter.createTool, #"{"prompt":"ein schwarz-weißes Bild"}"#)
        let edit = payload(ToolRouter.editTool, #"{"instruction":"in schwarz-weiß"}"#)
        let rewe = payload(ToolRouter.placeTool, #"{"query":"REWE","terms":["REWE"]}"#)
        let asked = LockedValue<[String]>([])
        let routed = await WishRouting.routed(wishes) { index, _, offersEdit in
            asked.mutate { $0.append("\(index)\(offersEdit ? "+" : "-")") }
            switch (index, offersEdit) {
            case (0, _): return ball
            case (1, false): return blind
            case (1, true): return edit
            default: return rewe
            }
        }
        XCTAssertEqual(routed.map(\.stepKind), [.create, .edit, .place])
        XCTAssertEqual(asked.current.sorted(), ["0-", "1+", "1-", "2-"],
                       "der Ortswunsch bekommt das Bildwerkzeug nie angeboten")
    }

    func testAGalleryWishBehindAPictureIsAskedAgainWithTheEditTool() async {
        let wishes = ["Zeig mir Bilder von Natalie Portman", "Mach das erste Bild schwarz-weiß"]
        let gallery = payload(ToolRouter.findTool, #"{"query":"Natalie Portman"}"#)
        let edit = payload(ToolRouter.editTool, #"{"instruction":"in schwarz-weiß"}"#)
        let asked = LockedValue<[String]>([])
        let routed = await WishRouting.routed(wishes) { index, _, offersEdit in
            asked.mutate { $0.append("\(index)\(offersEdit ? "+" : "-")") }
            return offersEdit ? edit : gallery
        }
        XCTAssertEqual(routed.map(\.stepKind), [.gallery, .edit],
                       "ein Galerie-Wunsch, der auf ein früheres Bild zeigt, darf die Bearbeitung werden")
        XCTAssertEqual(asked.current.sorted(), ["0-", "1+", "1-"])
    }

    func testManyWishesAreRoutedAllButNeverMoreThanThreeAtOnce() async {
        let wishes = (1...9).map { "Wunsch \($0)" }
        let calendar = payload(ToolRouter.calendarTool, #"{"action":"create","start":"2026-09-30 11:00"}"#)
        let running = LockedValue<(now: Int, most: Int)>((0, 0))
        let routed = await WishRouting.routed(wishes) { _, _, _ in
            running.mutate { $0.now += 1; $0.most = max($0.most, $0.now) }
            try? await Task.sleep(for: .milliseconds(40))
            running.mutate { $0.now -= 1 }
            return calendar
        }
        XCTAssertEqual(routed.count, 9, "jeder Wunsch bekommt seine Entscheidung")
        XCTAssertEqual(routed.map(\.wish), wishes, "die Reihenfolge des Nutzers bleibt")
        XCTAssertLessThanOrEqual(running.current.most, WishRouting.inFlight,
                                 "mehr gleichzeitige Anfragen löst beim Anbieter Throttling.BurstRate aus")
    }

    func testAWishAnsweredOnlyInChatGetsASecondOpinionAndARealActionWins() async {
        let wishes = ["Erstelle einen Termin morgen um 11 Uhr", "Wer war Albert Einstein?", "Wo ist die nächste Apotheke?"]
        let chat = payload(ToolRouter.answerTool, "{}")
        let calendar = payload(ToolRouter.calendarTool, #"{"action":"create","start":"2026-09-30 11:00"}"#)
        let place = payload(ToolRouter.placeTool, #"{"query":"Apotheke","terms":["Apotheke"]}"#)
        let asked = LockedValue<[Int: Int]>([:])
        let routed = await WishRouting.routed(wishes) { index, _, _ in
            let round = asked.mutate { counts -> Int in
                counts[index, default: 0] += 1
                return counts[index] ?? 0
            }
            switch (index, round) {
            case (0, 1): return chat
            case (0, _): return calendar
            case (1, _): return chat
            default: return place
            }
        }
        XCTAssertEqual(routed.map(\.stepKind), [.calendar, .chat, .place],
                       "ein Terminwunsch, der einmal im Chat landet, wird beim zweiten Blick zum Termin")
        XCTAssertEqual(asked.current, [0: 2, 1: 2, 2: 1], "nur Chat-Entscheidungen werden ein zweites Mal gefragt")
    }

    func testTheEditCandidatesAreExactlyThePictureAndAnswerWishesAfterAPictureMaker() {
        let chat = ToolDecision(route: .chat)
        let gallery = ToolDecision(route: .pictureSearch(query: "natalie portman"))
        let create = ToolDecision(route: .imageCreate, picturePrompt: "comic")
        let place = ToolDecision(route: .nearbyPlace(terms: ["REWE"], mode: .automatic))
        XCTAssertEqual(WishRouting.editCandidates([chat, gallery, create, place]), [2])
        XCTAssertEqual(WishRouting.editCandidates([chat, create]), [], "vor der Frage entsteht kein Bild")
        XCTAssertEqual(WishRouting.editCandidates([create, nil, chat]), [2])
        XCTAssertEqual(WishRouting.editCandidates([place, create]), [])
    }

    func testAPictureOfASplitWishKeepsTheUsersOwnWordsBesideTheRewrite() {
        var grau = ToolDecision(route: .imageCreate, picturePrompt: "A realistic portrait of the Mona Lisa")
        grau.wish = "Erstelle danach ein Schwarz-Weiß-Bild der Mona Lisa"
        let prompt = grau.pictureText(grau.picturePromptText, message: "ganzer Satz")
        XCTAssertTrue(prompt.hasPrefix("Erstelle danach ein Schwarz-Weiß-Bild der Mona Lisa"), prompt)
        XCTAssertTrue(prompt.contains("A realistic portrait of the Mona Lisa"), prompt)
        XCTAssertFalse(prompt.contains("ganzer Satz"), "die anderen Wünsche gehören nicht in dieses Bild")
        var blind = ToolDecision(route: .imageCreate)
        blind.wish = "Male mir einen Hund"
        XCTAssertEqual(blind.pictureText(blind.picturePromptText, message: "ganzer Satz"), "Male mir einen Hund")
        let single = ToolDecision(route: .imageEdit, pictureInstruction: "heller")
        XCTAssertEqual(single.pictureText(single.pictureInstructionText, message: "mach es heller"), "heller",
                       "ohne Zerlegung bleibt es beim Text des Routers")
        XCTAssertEqual(ToolDecision(route: .imageEdit).pictureText("", message: "mach es heller"), "mach es heller")
    }

    func testALaterWishKnowsWhatTheEarlierWishesDo() {
        let first = WishRouting.system("SYS", wish: 0, of: ["Male einen Ball", "Mach das neue Bild schwarz-weiß"],
                                       offersEdit: false)
        XCTAssertTrue(first.hasPrefix("SYS"))
        XCTAssertTrue(first.contains("exactly one call"), first)
        XCTAssertFalse(first.contains("Earlier wishes"), first)
        XCTAssertTrue(first.contains("1. Male einen Ball"), first)
        XCTAssertFalse(first.contains("already in the chat"), first)
        let second = WishRouting.system("SYS", wish: 1, of: ["Male einen Ball", "Mach das neue Bild schwarz-weiß"],
                                        offersEdit: false)
        XCTAssertTrue(second.contains("You answer only wish 2"), second)
        XCTAssertTrue(second.contains("1. Male einen Ball"), second)
        XCTAssertFalse(second.contains("already in the chat"), second)
        let withEdit = WishRouting.system("SYS", wish: 1, of: ["Male einen Ball", "Mach das neue Bild schwarz-weiß"],
                                          offersEdit: true)
        XCTAssertTrue(withEdit.contains("already in the chat for this wish"), withEdit)
        XCTAssertTrue(withEdit.contains("1. Male einen Ball"), withEdit)
        let earlierSection = withEdit.components(separatedBy: "Earlier wishes of the same message").last ?? ""
        XCTAssertFalse(earlierSection.contains("schwarz-weiß"),
                       "der eigene Wunsch steht nicht in der Vorgeschichte")
    }

    func testAFailingSplitAsksNothingOut() async {
        let nothing = await WishSplitter.splitParts(asking: { throw APIError(message: "kaputt") })
        XCTAssertNil(nothing)
    }

    func testAnUnreadableSplitAnswerStaysNil() async {
        let nothing = await WishSplitter.splitParts(asking: { "keine liste" })
        XCTAssertNil(nothing)
    }

    func testACutOffSplitAnswerKeepsTheFinishedWishes() async {
        let answer = #"{"wishes": ["Termin um 8 Uhr", "Male eine Ka"#
        let found = await WishSplitter.splitParts(asking: { answer })?.map(\.text)
        XCTAssertEqual(found, ["Termin um 8 Uhr"])
    }

    func testASplitWithoutAnAnswerReturnsNothing() async {
        let nothing = await WishSplitter.splitParts(asking: { nil })
        XCTAssertNil(nothing)
    }
}

@MainActor
final class AppointmentIdentityTests: GwenTestCase {
    private func plan(_ title: String?, _ start: String?) -> QwenAPI.CalendarPlan {
        var made = QwenAPI.CalendarPlan(action: .create)
        made.title = title
        made.start = start
        return made
    }

    func testABlankTitleBecomesTheDefaultTitleInsteadOfAnEmptyEvent() {
        XCTAssertEqual(plan("", nil).eventTitle, L.t("cal_default_title"))
        XCTAssertEqual(plan("   ", nil).eventTitle, L.t("cal_default_title"))
        XCTAssertEqual(plan(nil, nil).eventTitle, L.t("cal_default_title"))
        XCTAssertEqual(plan(" Banane ", nil).eventTitle, "Banane")
    }

    func testAnEmptyTitleNeverRenamesAnExistingAppointment() {
        XCTAssertNil(plan("", nil).givenTitle, "ein leerer Titel beim Ändern heißt: Name bleibt")
        XCTAssertNil(plan("  ", nil).givenTitle)
        XCTAssertNil(plan(nil, nil).givenTitle)
        XCTAssertEqual(plan(" Bananentreffen ", nil).givenTitle, "Bananentreffen")
    }

    func testTheSameGenericTitleAtAnotherTimeIsAnotherAppointment() throws {
        let carry = AnswerCarry()
        let eleven = try XCTUnwrap(Formatters.eventDate(from: "2026-09-30 11:00"))
        carry.notePlanned("✔ Termin angelegt", ref: CalendarRef(eventID: "ID-1",
                                                               title: plan(nil, nil).eventTitle,
                                                               start: eleven))
        XCTAssertFalse(carry.createdAlready(plan(nil, "2026-10-01 12:00")),
                       "der zweite Termin ohne Namen darf nicht als Doppel verworfen werden")
        XCTAssertFalse(carry.createdAlready(plan(L.t("cal_default_title"), "2026-10-01 12:00")))
        XCTAssertTrue(carry.createdAlready(plan(nil, "2026-09-30 11:00")), "derselbe Termin zweimal bleibt einer")
        XCTAssertTrue(carry.createdAlready(plan(L.t("cal_default_title"), "2026-09-30 11:00")))
        XCTAssertFalse(carry.createdAlready(plan("Zahnarzt", "2026-09-30 11:00")))
    }

    func testTheStepWordsCarryActionTitleSearchAndStart() {
        var plan = plan("Termin", "2026-09-30 11:00")
        XCTAssertEqual(plan.stepWords, "create Termin  2026-09-30 11:00")
        plan.action = .delete
        plan.find = "Zahnarzt"
        XCTAssertTrue(plan.stepWords.hasPrefix("delete"))
        XCTAssertTrue(plan.stepWords.contains("Zahnarzt"))
    }
}

final class WishIndependenceTests: GwenTestCase {
    func testTheSplitterNamesTheWishesThatNeedNothingEarlier() {
        let answer = #"{"wishes":["Wetter in Berlin?","Und wie spät ist es in Tokio?","Und was kostet die PS5?"],"independent":[1,2]}"#
        XCTAssertEqual(WishSplitter.parse(answer)?.parts,
                       [WishPart(text: "Wetter in Berlin?", independent: true),
                        WishPart(text: "Und wie spät ist es in Tokio?", independent: true),
                        WishPart(text: "Und was kostet die PS5?", independent: false)])
    }

    func testAnIndependentListWrittenAsStringsStillCounts() {
        let answer = #"{"wishes":["a","b"],"independent":["2"]}"#
        XCTAssertEqual(WishSplitter.parse(answer)?.parts.map(\.independent), [false, true])
        XCTAssertEqual(WishSplitter.parse(answer)?.parts.map(\.text), ["a", "b"],
                       "die Wunschliste bleibt eine Liste von Sätzen")
    }

    func testWithoutAReadableIndependentListNoWishRunsBesideAnother() {
        XCTAssertEqual(WishSplitter.parse(#"{"wishes":["a","b"]}"#)?.parts.map(\.independent),
                       [false, false])
        let text = WishSplitter.parse(#"{"wishes":["a"],"independent":"nein"}"#)?.parts.map(\.independent)
        XCTAssertEqual(text, [false])
        let truth = WishSplitter.parse(#"{"wishes":["a"],"independent":[true]}"#)?.parts.map(\.independent)
        XCTAssertEqual(truth, [false])
    }

    func testACutOffAnswerKeepsItsWishesButNoIndependenceClaim() {
        let cut = #"{"wishes": ["Termin um 8 Uhr", "Male eine Ka"#
        XCTAssertEqual(WishSplitter.parse(cut)?.parts,
                       [WishPart(text: "Termin um 8 Uhr", independent: false)])
    }

    func testTheSplitterIsAskedForTheIndependentWishes() {
        XCTAssertTrue(WishSplitter.system().contains("\"independent\""), WishSplitter.system())
        XCTAssertTrue(WishSplitter.system().contains("need nothing an earlier wish"), WishSplitter.system())
    }

    func testASplitThatIsCutOffStillDeliversTheIndependentWishes() async {
        let answer = #"{"wishes":["Wetter in Berlin?","Wie spät ist es in Tokio?"],"independent":[1,2]}"#
        let parts = await WishSplitter.splitParts(asking: { answer })
        XCTAssertEqual(parts?.map(\.text), ["Wetter in Berlin?", "Wie spät ist es in Tokio?"])
        XCTAssertEqual(parts?.map(\.independent), [true, true])
        let cut = await WishSplitter.splitParts(asking: { #"{"wishes":["a","b"# })
        XCTAssertEqual(cut, [WishPart(text: "a", independent: false)])
    }

    func testAWishThatNeedsNothingEarlierIsMarkedOnItsDecision() async {
        let wishes = ["Wetter in Berlin?", "Wie spät ist es in Tokio?", "Und was kostet die PS5?"]
        let weather = payload(ToolRouter.weatherTool, #"{"place":"Berlin"}"#)
        let clock = payload(ToolRouter.clockTool, #"{"timeZone":"Asia/Tokyo"}"#)
        let price = payload(ToolRouter.priceTool, #"{"terms":["PS5"]}"#)
        let routed = await WishRouting.routed(wishes, independent: [0, 1]) { index, _, _ in
            switch index {
            case 0: return weather
            case 1: return clock
            default: return price
            }
        }
        XCTAssertEqual(routed.map(\.wish), wishes)
        XCTAssertEqual(routed.map(\.standalone), [true, true, false],
                       "der Preiswunsch hängt an den früheren Wünschen")
    }

    func testTheSplitCarriesThePlaceAndListOfEveryWish() {
        let answer = #"{"wishes":["a","b"],"places":["Post","Post"],"lists":["",""]}"#
        let parts = WishSplitter.parse(answer)?.parts
        XCTAssertEqual(parts?.map(\.place), ["Post", "Post"])
        XCTAssertEqual(parts?.map(\.list), [nil, nil])
        XCTAssertEqual(parts?.map(\.placeKnown), [true, true])
    }

    func testAWishScopesItsReminderWithThePlaceAndListOfTheSplit() async throws {
        let plan = try JSONDecoder().decode(ReminderPlan.self,
                                            from: Data(#"{"action":"create","title":"Milch"}"#.utf8))
        let request = try XCTUnwrap(ReminderRequest(plan: plan))
        let part = WishPart(text: "wish", independent: true, place: "Post", list: "Einkauf",
                            placeKnown: true, listKnown: true)
        let scoped = await WishRouting.scoped([ToolDecision(route: .reminder(request))], parts: [part],
                                              lists: ["Einkauf"], placeExists: { @MainActor name in name == "Post" })
        guard case .reminder(let reminder) = scoped[0].route else {
            return XCTFail("expected a reminder")
        }
        XCTAssertEqual(reminder.place?.name, "Post")
        XCTAssertEqual(reminder.list, "Einkauf")
    }

    func testAWishDropsAnUnknownListAndNormalizesThePlace() async throws {
        let plan = try JSONDecoder().decode(ReminderPlan.self,
                                            from: Data(#"{"action":"create","title":"Milch"}"#.utf8))
        let request = try XCTUnwrap(ReminderRequest(plan: plan))
        let part = WishPart(text: "wish", independent: true, place: "einer Post", list: "Milch",
                            placeKnown: true, listKnown: true)
        let scoped = await WishRouting.scoped([ToolDecision(route: .reminder(request))], parts: [part],
                                              lists: ["Einkauf"], placeExists: { @MainActor name in name == "Post" })
        guard case .reminder(let reminder) = scoped[0].route else {
            return XCTFail("expected a reminder")
        }
        XCTAssertNil(reminder.list)
        XCTAssertEqual(reminder.place?.name, "Post")
    }

    func testFinalReminderListAndPlaceAreValidated() async throws {
        let plan = try JSONDecoder().decode(ReminderPlan.self,
                                            from: Data(#"{"action":"create","title":"Milch","list":"Hak","location":"Einkaufsliste"}"#.utf8))
        let request = try XCTUnwrap(ReminderRequest(plan: plan))
        let scoped = await WishRouting.scoped([ToolDecision(route: .reminder(request))], parts: nil,
                                              lists: ["Einkauf"],
                                              placeExists: { @MainActor name in name == "Post" })
        guard case .reminder(let reminder) = scoped[0].route else {
            return XCTFail("expected a reminder")
        }
        XCTAssertNil(reminder.list)
        XCTAssertNil(reminder.place)
    }

    func testAWishDropsAnUnresolvablePlace() async throws {
        let plan = try JSONDecoder().decode(ReminderPlan.self,
                                            from: Data(#"{"action":"create","title":"Milch"}"#.utf8))
        let request = try XCTUnwrap(ReminderRequest(plan: plan))
        let part = WishPart(text: "wish", independent: true, place: "Mondbasis", list: nil,
                            placeKnown: true, listKnown: false)
        let scoped = await WishRouting.scoped([ToolDecision(route: .reminder(request))], parts: [part],
                                              lists: [], placeExists: { @MainActor name in name == "Post" })
        guard case .reminder(let reminder) = scoped[0].route else {
            return XCTFail("expected a reminder")
        }
        XCTAssertNil(reminder.place)
    }

    func testTheSplitterDropsUnknownLists() {
        let answer = #"{"wishes":["a","b"],"lists":["Milch","Einkaufsliste"]}"#
        let parts = WishSplitter.parse(answer, knownLists: ["Einkauf"])?.parts
        XCTAssertEqual(parts?.map(\.list), [nil, "Einkauf"])
    }

    func testTheSplitterPromptDemandsExplicitListsAndPlaces() {
        let system = WishSplitter.system()
        XCTAssertTrue(system.contains("Fill places only when the wish is tied to a place"), system)
        XCTAssertTrue(system.contains("a thing to buy, do or tick off is not a list"), system)
    }

    func testTheWholePlanFillsAReminderThePerWishRouterLeftOpen() throws {
        let whole = ToolDecision(route: .reminder(try reminderRequest(
            #"{"action":"create","title":"Milch","find":"Milch","due":"2026-10-08 09:00","list":"Einkauf","location":"REWE","notes":"kalt","priority":"high","repeat":"daily","repeatInterval":2,"minutes":5,"seconds":10}"#)))
        let routed = ToolDecision(route: .reminder(try reminderRequest(#"{"action":"create"}"#)))
        let chosen = WishRouting.chosen(wishes: ["a", "b"], whole: [whole, whole], routed: [routed, routed])
        guard case .reminder(let merged) = chosen[0].route else {
            return XCTFail("expected a reminder")
        }
        XCTAssertEqual(merged.title, "Milch")
        XCTAssertEqual(merged.find, "Milch")
        XCTAssertEqual(merged.due, Formatters.eventDate(from: "2026-10-08 09:00"))
        XCTAssertEqual(merged.list, "Einkauf")
        XCTAssertEqual(merged.place?.name, "REWE")
        XCTAssertEqual(merged.notes, "kalt")
        XCTAssertEqual(merged.priority, .high)
        XCTAssertEqual(merged.repeatRule, ReminderRepeat(frequency: .daily, interval: 2))
        XCTAssertEqual(merged.minutes, 5)
        XCTAssertEqual(merged.seconds, 10)
    }

    private func reminderRequest(_ json: String) throws -> ReminderRequest {
        let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(json.utf8))
        return try XCTUnwrap(ReminderRequest(plan: plan))
    }

    func testAToolFromTheWholePlanBeatsAPerWishChatFallback() {
        let chat = ToolDecision(route: .chat)
        let status = ToolDecision(route: .appStatus)
        var first = chat
        first.wish = "a"
        first.standalone = true
        var second = chat
        second.wish = "b"
        second.standalone = true
        let chosen = WishRouting.chosen(wishes: ["a", "b"], whole: [chat, status],
                                        routed: [first, second])
        XCTAssertEqual(chosen.map(\.stepKind), [.chat, .status])
        XCTAssertEqual(chosen.map(\.wish), ["a", "b"])
        XCTAssertEqual(chosen.map(\.standalone), [true, true])
    }
}
