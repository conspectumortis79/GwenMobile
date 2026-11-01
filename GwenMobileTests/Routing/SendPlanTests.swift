@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SendPlanTests: GwenTestCase {
    func testTwoCallsStayTwoDecisionsInTheOrderTheModelGaveThem() throws {
        let data = payload([(ToolRouter.answerTool, "{}"),
                            (ToolRouter.editTool, "{\"instruction\":\"in schwarz-weiß\"}")])
        let decisions = ToolRouter.decisions(from: data)
        XCTAssertEqual(decisions.count, 2)
        XCTAssertEqual(decisions.first?.route, .chat)
        XCTAssertEqual(decisions.last?.route, .imageEdit)
        XCTAssertEqual(decisions.last?.pictureInstruction, "in schwarz-weiß")
    }

    func testTheEditToolSaysWhetherItOnlyTurnsThePictureBlackAndWhite() throws {
        let data = payload([(ToolRouter.editTool,
                             "{\"instruction\":\"in schwarz-weiß\",\"monochrome\":true}")])
        let decision = try XCTUnwrap(ToolRouter.decisions(from: data).first)
        XCTAssertTrue(decision.pictureMonochrome)
        XCTAssertFalse(ToolDecision(route: .imageEdit, pictureInstruction: "heller").pictureMonochrome,
                       "ohne das Argument bleibt jede andere Bearbeitung farbig")
    }

    func testTheMonochromeToolMarksTheLocalBlackAndWhitePath() throws {
        let decision = try XCTUnwrap(ToolRouter.map(name: ToolRouter.monochromeTool, arguments: "{}"))
        XCTAssertEqual(decision.route, .imageEdit)
        XCTAssertTrue(decision.pictureMonochrome)
        XCTAssertTrue(decision.pictureInstructionText.isEmpty)
    }

    func testTheFirstCallStillAnswersTheOldSingleToolQuestion() throws {
        let data = payload([(ToolRouter.editTool, "{\"instruction\":\"heller\"}")])
        let single = try XCTUnwrap(ToolRouter.decisions(from: data).first)
        XCTAssertEqual(single.route, .imageEdit)
    }

    func testAnUnreadableNameDropsOutInsteadOfBreakingTheChain() throws {
        let data = payload([(ToolRouter.answerTool, "{}"), ("wer_weiss_schon", "{}")])
        XCTAssertEqual(ToolRouter.decisions(from: data).count, 1)
    }

    func testThePlanKeepsOrderAndDropsTheSameKindTwice() {
        let plan = SendPlan.forming([ToolDecision(route: .chat),
                                     ToolDecision(route: .chat),
                                     ToolDecision(route: .imageEdit, pictureInstruction: "heller")])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.chat, .edit],
                       "zweimal dasselbe Werkzeug bleibt einmal, die Reihenfolge hält")
    }

    func testThePlanKeepsEveryWishWithoutAStepBudget() {
        let plan = SendPlan.forming([ToolDecision(route: .chat),
                                     ToolDecision(route: .imageEdit, pictureInstruction: "heller"),
                                     ToolDecision(route: .calendar),
                                     ToolDecision(route: .pictureSearch(query: "turm")),
                                     ToolDecision(route: .nearbyPlace(terms: ["kaufland"], mode: .walking))])
        XCTAssertEqual(plan.actions.count, 5)
        XCTAssertEqual(plan.traceLine, "chat+calendar+gallery+edit+place")
    }

    func testAReminderWishBehindAScanBecomesTheScanReminderButton() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"authority"}"#))
        let reminder = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                    arguments: #"{"action":"create","title":"Frist im Schreiben"}"#))
        let plan = SendPlan.forming([scan, reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case .scanDocument(let request) = plan.actions.first?.route else {
            return XCTFail("kein Scan: \(plan.traceLine)")
        }
        XCTAssertTrue(request.remind)
        XCTAssertEqual(request.kind, .authority)
    }

    func testAReminderWithItsOwnDateStaysBehindAScan() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"invoice"}"#))
        let reminder = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                    arguments: #"{"action":"create","title":"Zahnarzt","due":"2026-10-05 09:00"}"#))
        let plan = SendPlan.forming([scan, reminder])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.scan, .reminder])
        guard case .scanDocument(let request) = plan.actions.first?.route else {
            return XCTFail("kein Scan: \(plan.traceLine)")
        }
        XCTAssertFalse(request.remind)
    }

    func testAnEmptyPlanFallsBackToPlainChat() {
        let plan = SendPlan.forming([])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.primary.route, .chat)
    }

    func testATranslationKeepsItsPlaceInTheChain() {
        let plan = SendPlan.forming([ToolDecision(route: .chat),
                                     ToolDecision(route: .translate(TranslationJob(text: "a",
                                                                                   targetCode: "en")))])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.chat, .translate])
        XCTAssertFalse(plan.merges)
    }

    func testTwoTranslationsToDifferentTargetsStayTwoSteps() {
        let english = ToolDecision(route: .translate(TranslationJob(text: "a", targetCode: "en")))
        let french = ToolDecision(route: .translate(TranslationJob(text: "b", targetCode: "fr")))
        XCTAssertEqual(SendPlan.forming([english, french]).actions.map(\.stepKind), [.translate, .translate])
    }

    func testTwoCodeTasksInDifferentLanguagesStayTwoSteps() {
        let python = ToolDecision(route: .code(language: .python))
        let sql = ToolDecision(route: .code(language: .sql))
        XCTAssertEqual(SendPlan.forming([python, sql]).actions.map(\.stepKind), [.code, .code])
    }

    func testTwoCodeTasksWithDifferentWishesStayTwoSteps() {
        var first = ToolDecision(route: .code(language: .text))
        first.wish = "Schreibe eine Datei für den Plan"
        var second = ToolDecision(route: .code(language: .text))
        second.wish = "Schreibe eine Datei für die Tabelle"
        XCTAssertNotEqual(first.stepKey, second.stepKey)
        XCTAssertEqual(SendPlan.forming([first, second]).actions.count, 2)
    }

    func testOnlyChainsTheAppCanWriteIntoOneAnswerClaimToMerge() {
        XCTAssertTrue(SendPlan.forming([ToolDecision(route: .chat),
                                        ToolDecision(route: .imageEdit,
                                                     pictureInstruction: "heller")]).merges)
        XCTAssertTrue(SendPlan.forming([ToolDecision(route: .chat, searchQuery: "news"),
                                        ToolDecision(route: .calendar)]).merges)
        XCTAssertTrue(SendPlan.forming([ToolDecision(route: .nearbyPlace(terms: ["kaufland"],
                                                                        mode: .automatic)),
                                        ToolDecision(route: .chat, searchQuery: "öffnungszeiten")]).merges)
        XCTAssertFalse(SendPlan.forming([ToolDecision(route: .chat),
                                         ToolDecision(route: .priceSearch(terms: ["x"], country: nil,
                                                                          nearby: false))]).merges)
        XCTAssertFalse(SendPlan.singleChat.merges, "ein einzelner Schritt braucht nichts zu verschmelzen")
    }

    func testTheRouterIsToldItMayAnswerWithTwoCallsInOrder() {
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertFalse(system.contains("Choose exactly one tool"), system)
        XCTAssertTrue(system.contains("two calls"), system)
    }

    func testThePictureToolsTellTheModelHowToPairAQuestionWithAChange() throws {
        let tools = ToolRouter.tools(attachable: true)
        func description(_ name: String) throws -> String {
            let tool = try XCTUnwrap(tools.first {
                (($0["function"] as? [String: Any])?["name"] as? String) == name
            })
            return try XCTUnwrap((tool["function"] as? [String: Any])?["description"] as? String)
        }
        let answer = try description(ToolRouter.answerTool)
        XCTAssertTrue(answer.contains("first call"), answer)
        let edit = try description(ToolRouter.editTool)
        XCTAssertTrue(edit.contains("answer_in_chat first"), edit)
        let place = try description(ToolRouter.placeTool)
        XCTAssertTrue(place.contains("search_web the second"), place)
    }

    func testTheDecisionBudgetCarriesFourToolCalls() throws {
        let fields = ToolRouter.toolFields(maxTokens: ToolRouter.maxTokens,
                                           tools: ToolRouter.tools(attachable: true))
        XCTAssertEqual(fields["max_tokens"] as? Int, 700)
    }

    func testTheToolFieldsCarryTheBudgetWithoutAForcedChoice() throws {
        let fields = ToolRouter.toolFields(maxTokens: ToolRouter.maxTokens,
                                           tools: ToolRouter.tools(attachable: true), parallel: true)
        XCTAssertEqual(fields["max_tokens"] as? Int, 700)
        XCTAssertNil(fields["tool_choice"])
        XCTAssertNil(fields["parallel_tool_calls"])
    }

    func testAStructuredToolChoiceIsPassedThrough() throws {
        let forced: [String: Any] = ["type": "function",
                                     "function": ["name": ToolRouter.productTool]]
        let fields = ToolRouter.toolFields(maxTokens: ToolRouter.maxTokens,
                                           tools: ToolRouter.tools(attachable: false),
                                           toolChoice: forced)
        let choice = try XCTUnwrap(fields["tool_choice"] as? [String: Any])
        XCTAssertEqual(choice["type"] as? String, "function")
        let function = try XCTUnwrap(choice["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, ToolRouter.productTool)
    }

    func testFourWishesStayFourAndKeepTheirOrder() {
        let plan = SendPlan.forming([ToolDecision(route: .chat),
                                     ToolDecision(route: .imageEdit, pictureInstruction: "heller"),
                                     ToolDecision(route: .calendar),
                                     ToolDecision(route: .pictureSearch(query: "turm"))])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.chat, .calendar, .gallery, .edit],
                       "die Bearbeitung rutscht hinter die Suche, die ihr Bild liefert")
        XCTAssertEqual(plan.traceLine, "chat+calendar+gallery+edit")
    }

    func testTwelveWishesStayTwelveInTheirOrder() {
        var calls = (8...13).map { hour -> ToolDecision in
            var plan = QwenAPI.CalendarPlan(action: .create)
            plan.start = "2026-09-30 \(hour):00"
            return ToolDecision(route: .calendar, calendarPlan: plan)
        }
        calls += ["katze", "hund", "maus"].map { ToolDecision(route: .imageCreate, picturePrompt: $0) }
        calls += [ToolDecision(route: .pictureSearch(query: "dom")),
                  ToolDecision(route: .chat),
                  ToolDecision(route: .nearbyPlace(terms: ["apotheke"], mode: .walking))]
        let plan = SendPlan.forming(calls)
        XCTAssertEqual(plan.actions.count, 12, "kein Wunsch fällt einem Stufenbudget zum Opfer")
        XCTAssertEqual(plan.traceLine, Array(repeating: "calendar", count: 6).joined(separator: "+")
                       + "+create+create+create+gallery+chat+place")
    }

    func testTheSameTaskInTheSameWordsStaysOneStepAndTwoDifferentChangesStayTwo() {
        XCTAssertEqual(SendPlan.forming([ToolDecision(route: .imageEdit, pictureInstruction: "heller"),
                                         ToolDecision(route: .imageEdit, pictureInstruction: "heller")])
                        .actions.count, 1, "derselbe Auftrag in denselben Worten ist keine zweite Stufe")
        XCTAssertEqual(SendPlan.forming([ToolDecision(route: .imageEdit, pictureInstruction: "heller"),
                                         ToolDecision(route: .imageEdit, pictureInstruction: "dunkler")])
                        .actions.count, 2, "zwei verschiedene Eingriffe desselben Werkzeugs sind zwei Aufgaben")
    }

    func testThreeWishesKeepTheOrderTheUserWroteThem() {
        let chat = ToolDecision(route: .chat)
        let gallery = ToolDecision(route: .pictureSearch(query: "natalie portman"))
        let edit = ToolDecision(route: .imageEdit, pictureInstruction: "mache das erste bild schwarz-weiß")
        XCTAssertEqual(SendPlan.forming([chat, gallery, edit]).actions.map(\.stepKind), [.chat, .gallery, .edit])
    }

    func testASecondAppointmentIsAllowedAndOnlyItsDuplicateIsDropped() {
        let zwei = SendPlan.forming([ToolDecision(route: .calendar, calendarPlan: plan("GwenA")),
                                     ToolDecision(route: .calendar, calendarPlan: plan("GwenB"))])
        XCTAssertEqual(zwei.actions.count, 2, "zwei betitelte Termine sind zwei Aufgaben")
        let doppelt = SendPlan.forming([ToolDecision(route: .calendar, calendarPlan: plan("GwenA")),
                                        ToolDecision(route: .calendar, calendarPlan: plan("GwenA"))])
        XCTAssertEqual(doppelt.actions.count, 1, "derselbe Termin zweimal ist keine zweite Aufgabe")
    }

    func testTwoUnnamedAppointmentsAtDifferentTimesStayTwoSteps() {
        let elf = ToolDecision(route: .calendar, calendarPlan: plan("Termin", at: "2026-09-30 11:00"))
        let zwoelf = ToolDecision(route: .calendar, calendarPlan: plan("Termin", at: "2026-10-01 12:00"))
        XCTAssertNotEqual(elf.stepKey, zwoelf.stepKey)
        XCTAssertEqual(SendPlan.forming([elf, zwoelf]).actions.count, 2,
                       "derselbe Allerweltstitel zu zwei Uhrzeiten sind zwei Termine")
        let ohneTitel = ToolDecision(route: .calendar, calendarPlan: plan(nil, at: "2026-10-01 12:00"))
        XCTAssertEqual(SendPlan.forming([elf, ohneTitel]).actions.count, 2)
        XCTAssertEqual(SendPlan.forming([elf, elf]).actions.count, 1)
    }

    func testTwoWishesWhoseRouterDataCollideStayTwoSteps() {
        var neun = ToolDecision(route: .calendar, calendarPlan: plan(nil, at: "2026-09-30 08:00"))
        neun.wish = "Trag einen Termin morgen um 9 Uhr ein"
        var acht = ToolDecision(route: .calendar, calendarPlan: plan(nil, at: "2026-09-30 08:00"))
        acht.wish = "Trag einen Termin morgen um 8 Uhr ein"
        XCTAssertEqual(SendPlan.forming([acht, neun]).actions.count, 2,
                       "die Zerlegung hat zwei Wünsche gezählt; eine falsche Router-Uhrzeit macht daraus kein Doppel")
        XCTAssertEqual(SendPlan.forming([acht, acht]).actions.count, 1)
    }

    func testTwoQuestionsStayOneChatStepBecauseItAnswersTheWholeMessage() {
        var einstein = ToolDecision(route: .chat)
        einstein.wish = "Wer war Albert Einstein?"
        var curie = ToolDecision(route: .chat)
        curie.wish = "Wer war Marie Curie?"
        XCTAssertEqual(SendPlan.forming([einstein, curie]).actions.count, 1)
        XCTAssertEqual(einstein.stepKey, "chat|")
    }

    func testTwoWishesRoutedToTheVerySameGalleryStayOneGallery() {
        var wer = ToolDecision(route: .pictureSearch(query: "Natalie Portman"))
        wer.wish = "wer ist natalie portman ?"
        var bilder = ToolDecision(route: .pictureSearch(query: "Natalie Portman"))
        bilder.wish = "Zeig mir Bilder von Natalie Portman."
        XCTAssertEqual(SendPlan.forming([wer, bilder]).actions.count, 1,
                       "dieselbe Suche zweimal wäre dieselbe Galerie zweimal")
    }

    func testTwoDeletesWithDifferentSearchWordsStayTwoSteps() {
        let a = ToolDecision(route: .calendar, calendarPlan: planFind("Zahnarzt", .delete))
        let b = ToolDecision(route: .calendar, calendarPlan: planFind("Friseur", .delete))
        XCTAssertEqual(SendPlan.forming([a, b]).actions.count, 2)
    }

    private func plan(_ title: String?, at start: String) -> QwenAPI.CalendarPlan {
        var made = QwenAPI.CalendarPlan(action: .create)
        made.title = title
        made.start = start
        return made
    }

    private func plan(_ title: String) -> QwenAPI.CalendarPlan {
        var made = QwenAPI.CalendarPlan(action: .create)
        made.title = title
        return made
    }

    func testOnlyStepsThatNeedAnExistingEventAreCheckedBeforeTheyRun() {
        var create = QwenAPI.CalendarPlan(action: .create)
        create.title = "GwenKurz"
        XCTAssertFalse(create.needsExistingEvent, "anlegen braucht nichts Vorhandenes")
        XCTAssertTrue(create.needsPlannerPass)
        var move = QwenAPI.CalendarPlan(action: .update)
        move.title = "GwenKurz"
        XCTAssertTrue(move.needsExistingEvent)
        XCTAssertFalse(move.needsPlannerPass, "ein Update behält seine eigenen Felder")
        var remove = QwenAPI.CalendarPlan(action: .delete)
        remove.find = "Zahnarzt"
        XCTAssertTrue(remove.needsExistingEvent)
        XCTAssertEqual(remove.lookupWords, "Zahnarzt")
        XCTAssertEqual(move.lookupWords, "GwenKurz", "ohne Suchwort ist der Titel das Suchwort")
    }

    func testThePlannerIsToldWhatThisMessageAlreadyScheduled() {
        let leer = Prompt.Router.calendar(tz: "UTC+02:00", now: "So 2026-09-28 18:00", events: "",
                                          calendars: "", history: "", planned: "")
        XCTAssertFalse(leer.contains("Already planned"), leer)
        let besetzt = Prompt.Router.calendar(tz: "UTC+02:00", now: "So 2026-09-28 18:00", events: "",
                                             calendars: "", history: "",
                                             planned: "✔ Termin angelegt: Banane — Di 11:00")
        XCTAssertTrue(besetzt.contains("Already planned from this very message"), besetzt)
        XCTAssertTrue(besetzt.contains("Banane"), besetzt)
        XCTAssertTrue(besetzt.contains("answer action \"none\""), besetzt)
    }

    func testTheAnswerPromptForbidsClaimsOfMissingAppAbilities() {
        let prompt = L.t("picture_honesty_prompt")
        XCTAssertTrue(prompt.contains("Bilder zeigen") || prompt.contains("pictures"), prompt)
        XCTAssertTrue(prompt.contains("Kalender") || prompt.contains("calendar"), prompt)
        XCTAssertTrue(prompt.contains("offen geblieben") || prompt.contains("stayed undone"), prompt)
        XCTAssertFalse(prompt.contains("kann keine Bilder"), prompt)
    }

    func testEveryNewAppointmentIsPlannedByTheDedicatedPlanner() {
        var made = QwenAPI.CalendarPlan(action: .create)
        made.title = "Banane"
        made.start = "2026-10-03 11:00"
        XCTAssertTrue(made.needsPlannerPass,
                      "das Werkzeug routet nur, Titel und Uhrzeit holt der Terminplaner")
        var naked = QwenAPI.CalendarPlan(action: .create)
        naked.title = "Banane"
        XCTAssertTrue(naked.needsPlannerPass)
        var remove = QwenAPI.CalendarPlan(action: .delete)
        remove.find = "Banane"
        XCTAssertFalse(remove.needsPlannerPass, "ändern und löschen bleiben beim Werkzeugplan")
        var move = QwenAPI.CalendarPlan(action: .update)
        move.find = "Banane"
        XCTAssertFalse(move.needsPlannerPass)
    }

    func testAStepThatNeedsAnExistingEventNeverRunsBeforeItsOwnCreate() {
        let update = ToolDecision(route: .calendar, calendarPlan: planFind("GwenErst", .update))
        let made = ToolDecision(route: .calendar, calendarPlan: plan("GwenErst"))
        let plan = SendPlan.forming([update, made])
        XCTAssertEqual(plan.actions.count, 2, "unterschiedliche Schlüssel bleiben zwei Aufgaben")
        XCTAssertFalse(plan.actions.first?.needsExistingEvent ?? true,
                       "erst anlegen, dann ändern - sonst sucht das Update ein Ereignis, das es noch nicht gibt")
        XCTAssertTrue(plan.actions.last?.needsExistingEvent ?? false)
    }

    private func planFind(_ words: String, _ action: QwenAPI.CalendarPlan.Action) -> QwenAPI.CalendarPlan {
        var made = QwenAPI.CalendarPlan(action: action)
        made.find = words
        return made
    }

    func testAPictureChangeWaitsForTheSearchThatSuppliesItsPicture() {
        let edit = ToolDecision(route: .imageEdit, pictureInstruction: "mache das erste bild schwarz-weiß")
        let gallery = ToolDecision(route: .pictureSearch(query: "natalie portman"))
        let chat = ToolDecision(route: .chat)
        let plan = SendPlan.forming([chat, edit, gallery])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.chat, .gallery, .edit],
                       "ohne die Fundstücke hat die Bearbeitung kein Ziel")
        let alone = SendPlan.forming([edit])
        XCTAssertEqual(alone.actions.map(\.stepKind), [.edit], "eine einzelne Bearbeitung bleibt stehen")
        let keepOrder = SendPlan.forming([gallery, edit])
        XCTAssertEqual(keepOrder.actions.map(\.stepKind), [.gallery, .edit])
        var created = ToolDecision(route: .imageCreate, picturePrompt: "Hund")
        created.wish = "Male einen Hund"
        var change = ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiß")
        change.wish = "Mach ihn schwarz-weiß"
        var pictures = ToolDecision(route: .pictureSearch(query: "Katzen"))
        pictures.wish = "Zeig mir Bilder von Katzen"
        XCTAssertEqual(SendPlan.forming([created, change, pictures]).actions.map(\.stepKind),
                       [.create, .edit, .gallery],
                       "mit eigenen Wünschen bleibt die Reihenfolge des Nutzers erhalten")
        XCTAssertEqual(SendPlan.forming([chat, created, change, gallery]).actions.map(\.stepKind),
                       [.chat, .create, .edit, .gallery],
                       "ein vorhandenes Bild ist das Ziel der Bearbeitung, nicht die spätere Galerie")
    }

    func testAPictureStepWithoutItsOwnInstructionOnlyRunsAsTheOnlyStep() {
        let blind = ToolDecision(route: .imageEdit)
        XCTAssertTrue(blind.canRunAsPictureStep(number: 1),
                      "ist die Bearbeitung der ganze Auftrag, ist der Satz selbst die Anweisung")
        XCTAssertFalse(blind.canRunAsPictureStep(number: 2),
                       "in einer Kette würde der ganze Satz als Anweisung ein falsches Bild malen")
        let named = ToolDecision(route: .imageEdit, pictureInstruction: "mache es schwarz-weiß")
        XCTAssertTrue(named.canRunAsPictureStep(number: 2))
        XCTAssertTrue(ToolDecision(route: .imageCreate, picturePrompt: "ball").canRunAsPictureStep(number: 3))
        XCTAssertFalse(ToolDecision(route: .imageCreate).canRunAsPictureStep(number: 2),
                       "ein Bild ohne eigene Beschreibung würde den ganzen Satz als Motiv malen")
        XCTAssertTrue(ToolDecision(route: .imageCreate).canRunAsPictureStep(number: 1))
        var eigenerWunsch = ToolDecision(route: .imageCreate)
        eigenerWunsch.wish = "Male mir einen Hund"
        XCTAssertTrue(eigenerWunsch.canRunAsPictureStep(number: 2), "der eigene Wunsch ist die Beschreibung")
        XCTAssertEqual(eigenerWunsch.ownWords(or: "Male mir eine Katze und danach einen Hund"),
                       "Male mir einen Hund")
        XCTAssertEqual(blind.ownWords(or: "ganzer Satz"), "ganzer Satz")
    }

    func testAnEmptyContextNoteAddsNoHollowMessageButThePicture() {
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "frag")], images: [])
        let grown = turn.continuing(after: "", pictures: [Data([7])], files: ["fund.jpg"])
        XCTAssertEqual(grown.messages.count, 1, "eine Bildübergabe schreibt keine leere Antwort in den Verlauf")
        XCTAssertEqual(grown.pictureFiles, ["fund.jpg"])
        XCTAssertTrue(grown.needsVision)
    }

    func testAPlanDropsABlindPictureStepOnlyWhenItWouldLeaveSomethingBehind() {
        let blind = ToolDecision(route: .imageEdit)
        let create = ToolDecision(route: .imageCreate, picturePrompt: "roter ball")
        let both = SendPlan.forming([create, blind])
        XCTAssertEqual(both.actions.map(\.stepKind), [.create],
                       "eine Bearbeitung ohne eigene Anweisung malt ein falsches Bild, also bleibt sie weg")
        let only = SendPlan.forming([blind, create])
        XCTAssertEqual(only.actions.map(\.stepKind), [.create])
        let single = SendPlan.forming([blind])
        XCTAssertEqual(single.actions.map(\.stepKind), [.edit],
                       "ist sie der ganze Auftrag, ist der Satz selbst die Anweisung")
        let named = SendPlan.forming([create, ToolDecision(route: .imageEdit,
                                                           pictureInstruction: "schwarz-weiß")])
        XCTAssertEqual(named.actions.map(\.stepKind), [.create, .edit])
    }

    func testTheStepKeyCarriesTheWordsThatTellTasksApart() {
        let hell = ToolDecision(route: .imageEdit, pictureInstruction: "Mache das Bild Heller")
        let gelb = ToolDecision(route: .imageEdit, pictureInstruction: "mache das bild gelb")
        XCTAssertNotEqual(hell.stepKey, gelb.stepKey)
        XCTAssertEqual(hell.stepKey,
                       ToolDecision(route: .imageEdit,
                                    pictureInstruction: "mache   das bild  heller").stepKey,
                       "Leerraum und Großschreibung machen noch keinen zweiten Auftrag")
        XCTAssertEqual(ToolDecision(route: .imageCreate, picturePrompt: "Mona Lisa in Schwarz-Weiß").stepKey,
                       ToolDecision(route: .imageCreate, picturePrompt: "MONA LISA IN SCHWARZ-WEISS").stepKey,
                       "Groß- und Kleinschreibung sowie ß und ss sind derselbe Auftrag")
        XCTAssertEqual(ToolDecision(route: .chat).stepKey, "chat|")
    }

    func testTwoPriceTasksDifferByTheirTerms() {
        let macbook = ToolDecision(route: .priceSearch(terms: ["macbook pro 13", "32gb ram", "1tb ssd"],
                                                       country: nil, nearby: false))
        let studio = ToolDecision(route: .priceSearch(terms: ["mac studio m5 ultra", "256gb ram"],
                                                      country: nil, nearby: false))
        XCTAssertNotEqual(macbook.stepKey, studio.stepKey)
        let plan = SendPlan.forming([macbook, studio])
        XCTAssertEqual(plan.actions.count, 2, "zwei Geräte sind zwei Preisaufgaben")
        XCTAssertEqual(plan.traceLine, "price+price")
    }

    func testThePriceKeyAlsoSeparatesCountryAndNearby() {
        let zuhause = ToolDecision(route: .priceSearch(terms: ["regal"], country: "Polen", nearby: false))
        let nebenan = ToolDecision(route: .priceSearch(terms: ["regal"], country: nil, nearby: true))
        let gleichesLand = ToolDecision(route: .priceSearch(terms: ["regal"], country: "Polen", nearby: false))
        XCTAssertNotEqual(zuhause.stepKey, nebenan.stepKey)
        XCTAssertEqual(zuhause.stepKey, gleichesLand.stepKey)
    }

    func testTwoPlaceTasksDifferByTermsAndTravelMode() {
        let apotheke = ToolDecision(route: .nearbyPlace(terms: ["apotheke"], mode: .walking))
        let markt = ToolDecision(route: .nearbyPlace(terms: ["kaufland"], mode: .walking))
        let fahrrad = ToolDecision(route: .nearbyPlace(terms: ["apotheke"], mode: .cycling))
        XCTAssertNotEqual(apotheke.stepKey, markt.stepKey)
        XCTAssertNotEqual(apotheke.stepKey, fahrrad.stepKey)
    }

    func testThreeTasksInOneMessageFitTheBudgetAndStaySeparateBubbles() throws {
        let data = payload([(ToolRouter.priceTool,
                             #"{"terms":["macbook pro 13","32gb","1tb"]}"#),
                            (ToolRouter.priceTool,
                             #"{"terms":["mac studio m5 ultra","256gb","1tb"]}"#),
                            (ToolRouter.findTool, #"{"query":"mac studio m5 ultra"}"#)])
        let plan = SendPlan.forming(ToolRouter.decisions(from: data))
        XCTAssertEqual(plan.actions.count, 3)
        XCTAssertEqual(plan.traceLine, "price+price+gallery")
        XCTAssertFalse(plan.merges, "eine Preisrunde füllt eine eigene Blase, also bekommt jede ihre")
    }

    func testThreePictureVariantsInOneSentenceStayThreeSteps() {
        let ball = ToolDecision(route: .imageCreate, picturePrompt: "ein roter Ball auf weißem Grund")
        let grau = ToolDecision(route: .imageCreate, picturePrompt: "derselbe Ball als Schwarz-Weiß-Bild")
        let comic = ToolDecision(route: .imageCreate, picturePrompt: "derselbe Ball comic-artig gezeichnet")
        let plan = SendPlan.forming([ball, grau, comic])
        XCTAssertEqual(plan.actions.count, 3)
        XCTAssertEqual(Set(plan.actions.map(\.stepKey)).count, 3, "jede Variante hat ihren eigenen Schlüssel")
        XCTAssertTrue(plan.merges, "alle Varianten gehören in eine Blase")
        XCTAssertEqual(plan.traceLine, "create+create+create")
    }

    func testAScanReminderBeforeItsScanBecomesTheButtonToo() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"authority"}"#))
        let reminder = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                    arguments: #"{"action":"create","title":"Frist"}"#))
        let plan = SendPlan.forming([reminder, scan])
        XCTAssertEqual(plan.actions.count, 1)
        guard case .scanDocument(let request) = plan.actions.first?.route else {
            return XCTFail("kein Scan: \(plan.traceLine)")
        }
        XCTAssertTrue(request.remind)
    }

    func testEveryScanAbsorbsItsOwnReminderEvenAfterAnEarlierOne() throws {
        let authority = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                     arguments: #"{"kind":"authority"}"#))
        let invoice = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool, arguments: #"{"kind":"invoice"}"#))
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                 arguments: #"{"action":"create","title":"Frist Amt"}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                  arguments: #"{"action":"create","title":"Frist Rechnung"}"#))
        let plan = SendPlan.forming([first, authority, invoice, second])
        XCTAssertEqual(plan.traceLine, "scan+scan")
        let reminds = plan.actions.map { action -> Bool in
            guard case .scanDocument(let request) = action.route else { return false }
            return request.remind
        }
        XCTAssertEqual(reminds, [true, true])
    }

    func testAScanReminderBehindAMovedAppointmentStillBecomesTheButton() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"authority"}"#))
        var move = QwenAPI.CalendarPlan(action: .update)
        move.find = "Zahnarzt"
        let reminder = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                    arguments: #"{"action":"create","title":"Frist"}"#))
        let plan = SendPlan.forming([scan, ToolDecision(route: .calendar, calendarPlan: move), reminder])
        XCTAssertEqual(plan.traceLine, "scan+calendar")
        guard case .scanDocument(let request) = plan.actions.first?.route else {
            return XCTFail("kein Scan: \(plan.traceLine)")
        }
        XCTAssertTrue(request.remind)
    }

    func testAChainOfPictureStepsKeepsEveryEarlierPictureInTheDocument() {
        var carry = AnswerArtifacts()
        for file in ["ball.jpg", "ball_schwarzweiss.jpg", "ball_comic.jpg"] {
            carry = carry.merged(with: AnswerArtifacts(outImages: [Attachment(file: file)]))
        }
        XCTAssertEqual(carry.outImages?.map(\.file),
                       ["ball.jpg", "ball_schwarzweiss.jpg", "ball_comic.jpg"])
    }

    func testTheThirdStepSeesThePictureOfTheSecondStep() {
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Ball, dann s/w, dann comic")],
                             images: [], pictureFiles: [])
        let zweite = turn.continuing(after: "Ball ist gezeichnet.", pictures: [Data([1])],
                                     files: ["ball.jpg"])
        let dritte = zweite.continuing(after: "Schwarz-Weiß ist fertig.", pictures: [Data([2])],
                                       files: ["ball_schwarzweiss.jpg"])
        XCTAssertEqual(dritte.pictureFiles, ["ball.jpg", "ball_schwarzweiss.jpg"])
        XCTAssertEqual(dritte.positions(of: ["ball_schwarzweiss.jpg"]), [2],
                       "die dritte Stufe greift auf das Bild der zweiten zu")
        XCTAssertEqual(dritte.messages.count, 3, "beide Antworten stehen über der dritten Stufe")
    }

    func testTwoDifferentPictureTasksBecomeTwoStepsAndOneRepeatStaysOne() {
        let zwei = SendPlan.forming([ToolDecision(route: .imageCreate,
                                                  picturePrompt: "Mona Lisa in Schwarz-Weiß"),
                                     ToolDecision(route: .imageCreate,
                                                  picturePrompt: "Mona Lisa mit deutlichem Gelbstich")])
        XCTAssertEqual(zwei.actions.count, 2, "gleiche Art, andere Worte = zwei Aufgaben")
        XCTAssertTrue(zwei.merges, "beide Bilder passen in eine Blase")
        let gleich = SendPlan.forming([ToolDecision(route: .imageCreate,
                                                    picturePrompt: "Mona Lisa in Schwarz-Weiß"),
                                       ToolDecision(route: .imageCreate,
                                                    picturePrompt: "  mona lisa in SCHWARZ-WEISS ")])
        XCTAssertEqual(gleich.actions.count, 1, "wortgleich bleibt eine Stufe, auch andrer Schreibweise")
    }

    func testTwoStepsFightingForOneSlotGetTheirOwnBubbles() {
        XCTAssertFalse(SendPlan.forming([ToolDecision(route: .pictureSearch(query: "a")),
                                         ToolDecision(route: .pictureSearch(query: "b"))]).merges,
                       "zwei Galerien teilen sich ein Feld, also zwei Blasen")
        let zweiTermine = SendPlan.forming([ToolDecision(route: .calendar, calendarPlan: plan("GwenA")),
                                            ToolDecision(route: .calendar, calendarPlan: plan("GwenB"))])
        XCTAssertEqual(zweiTermine.actions.count, 2, "zwei betitelte Termine sind zwei Aufgaben")
        XCTAssertFalse(zweiTermine.merges, "ein Terminfeld passt nur einmal in eine Blase")
        XCTAssertTrue(SendPlan.forming([ToolDecision(route: .chat),
                                        ToolDecision(route: .imageCreate, picturePrompt: "x")]).merges)
        XCTAssertTrue(SendPlan.forming([ToolDecision(route: .chat),
                                        ToolDecision(route: .imageEdit,
                                           pictureInstruction: "heller")]).merges)
    }
}

@MainActor
final class AnswerCarryTests: GwenTestCase {
    private func picture(_ file: String) -> WebPicture {
        WebPicture(file: file, pageURL: "https://q.test/s", fullURL: "https://q.test/bild.jpg",
                   title: file, domain: "q.test")
    }

    func testTheCarriesTextStaysInStepOrder() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "eins"))
        carry.add(AnswerPiece(text: "  "))
        carry.add(AnswerPiece(text: "zwei"))
        XCTAssertEqual(carry.text, "eins\n\nzwei", "leere Stufen schreiben keinen Leerlauf in die Blase")
    }

    func testTheTextSinceACursorCarriesOnlyTheFreshStepsAndKeepsTheirSourceNumbers() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "alt [1]", artifacts: AnswerArtifacts(sources: [Fixtures.source("a", "https://a", "a")])))
        carry.add(AnswerPiece(text: "neu [1]", artifacts: AnswerArtifacts(sources: [Fixtures.source("b", "https://b", "b")])))
        XCTAssertEqual(carry.text(since: 1), "neu [2]")
        XCTAssertEqual(carry.text(since: 2), "")
        XCTAssertEqual(carry.text(since: -1), carry.text)
        XCTAssertEqual(carry.text(since: 9), "")
    }

    func testTheFreshPiecesStartAtTheCursorAndClampBothEnds() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "eins"))
        carry.add(AnswerPiece(text: "zwei"))
        XCTAssertEqual(carry.freshPieces(since: 0).map(\.text), ["eins", "zwei"])
        XCTAssertEqual(carry.freshPieces(since: 1).map(\.text), ["zwei"])
        XCTAssertTrue(carry.freshPieces(since: 8).isEmpty)
        XCTAssertEqual(carry.freshPieces(since: -2).count, 2)
    }

    func testTheLastAnsweredTextSkipsArtifactsWithoutWords() {
        let carry = AnswerCarry()
        XCTAssertEqual(carry.lastAnswerText, "")
        carry.add(AnswerPiece(text: "", artifacts: AnswerArtifacts(outImages: [Attachment(file: "a.jpg")])))
        XCTAssertEqual(carry.lastAnswerText, "")
        carry.add(AnswerPiece(text: "fertig"))
        carry.add(AnswerPiece(text: "  "))
        XCTAssertEqual(carry.lastAnswerText, "fertig")
    }

    func testArtifactsOfEveryStepLandInTheSameMessage() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Frage",
                              artifacts: AnswerArtifacts(sources: [Fixtures.source("a", "https://a", "a")]),
                              model: "chat"))
        carry.add(AnswerPiece(text: "Antwort",
                              artifacts: AnswerArtifacts(outImages: [Attachment(file: "img_neu.jpg")],
                                                         calendarRef: CalendarRef(eventID: "ID-1",
                                                                                  title: "Blubb",
                                                                                  start: Date())),
                              model: "bild"))
        let held = carry.artifacts
        XCTAssertEqual(held.sources?.count, 1)
        XCTAssertEqual(held.outImages?.map(\.file), ["img_neu.jpg"])
        XCTAssertNotNil(held.calendarRef)
        XCTAssertEqual(carry.model, "bild", "die letzte Stufe signiert die gemeinsame Antwort")
    }

    func testTwoEditedPicturesBothStayInTheDocument() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "eins", artifacts: AnswerArtifacts(outImages: [Attachment(file: "a.jpg")])))
        carry.add(AnswerPiece(text: "zwei", artifacts: AnswerArtifacts(outImages: [Attachment(file: "b.jpg")])))
        XCTAssertEqual(carry.artifacts.outImages?.map(\.file), ["a.jpg", "b.jpg"])
    }

    func testTheGalleryOfTheLaterStepWinsAndNothingFallsOutOfTheMessage() {
        let small = PictureGallery(query: "a", pictures: [picture("x")])
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "galerie", artifacts: AnswerArtifacts(gallery: small)))
        XCTAssertEqual(carry.artifacts.gallery?.pictures.count, 1)
        XCTAssertNil(carry.artifacts.outImages, "ohne Bilder darf kein leeres Feld in der Nachricht stehen")
    }

    func testTheCarryRemembersWhichAppointmentsThisChainAlreadyFiled() {
        let carry = AnswerCarry()
        XCTAssertFalse(carry.hasPlannedAppointment, "am Anfang ist nichts eingeplant")
        XCTAssertEqual(carry.plannedText, "")
        carry.notePlanned("✔ Termin angelegt: Banane — Di., 29. Sept. 11:00")
        carry.notePlanned("   ")
        XCTAssertTrue(carry.hasPlannedAppointment)
        XCTAssertEqual(carry.plannedText, "✔ Termin angelegt: Banane — Di., 29. Sept. 11:00",
                       "leere Meldungen schreiben keinen Leerlauf in den Planerkontext")
    }

    func testAnEventCreatedEarlierInThisChainCountsAsExisting() {
        let carry = AnswerCarry()
        let ref = CalendarRef(eventID: "ID-1", title: "GwenErst", start: Date())
        carry.notePlanned("✔ Termin angelegt: GwenErst", ref: ref)
        XCTAssertTrue(carry.createdAppointment(named: "GwenErst"),
                      "ein gerade erzeugter Termin ist vorhanden, auch wenn EventKit ihn noch nicht zeigt")
        XCTAssertTrue(carry.createdAppointment(named: "gwen erst"))
        XCTAssertFalse(carry.createdAppointment(named: "Zahnarzt"))
    }

    func testTheNextStepAlsoReceivesTheFirstFoundPicture() async throws {
        let media = scratchMediaStore()
        guard let file = media.storeImageData(FakePictureData.jpeg()) else { return XCTFail("kein Bild") }
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "18 Bildtreffer.",
                              artifacts: AnswerArtifacts(gallery: PictureGallery(query: "a",
                                                                                 pictures: [picture(file)]))))
        let routed = RoutedSend(text: "und das erste davon in schwarz-weiß",
                                plan: SendPlan.singleChat,
                                turn: ModelTurn(messages: [], images: []),
                                history: [], attachments: [], files: [], convID: UUID(), started: Date())
        let weiter = await routed.continuing(with: carry, since: 0, media: media)
        XCTAssertEqual(weiter.turn.pictureFiles, [file],
                       "ohne das Fundstück hat die Bearbeitungsstufe kein Ziel")
        XCTAssertEqual(weiter.turn.images.count, 1)
    }
}

@MainActor
final class ChainMessageWriterTests: GwenTestCase {
    private func store() -> ChatStore {
        let paths = StoragePaths(documents: tempDocuments())
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheWholeChainWritesOneMessageAndEveryPictureLandsOnce() throws {
        let store = store()
        let convID = try XCTUnwrap(store.currentID)
        let writer = ChainMessageWriter()
        let started = Date()
        let slot = AnswerSlot(writer: writer)
        slot.store(AnswerPiece(text: "Natalie Portman ist eine Schauspielerin.", model: "chat"),
                   to: store, convID: convID, started: started)
        slot.store(AnswerPiece(text: "18 Bildtreffer.",
                               artifacts: AnswerArtifacts(gallery: PictureGallery(
                                 query: "natalie",
                                 pictures: [WebPicture(file: "a.jpg", pageURL: "https://q",
                                                       fullURL: "https://q/a", title: "t",
                                                       domain: "q")]))),
                   to: store, convID: convID, started: started)
        slot.store(AnswerPiece(text: "Hier ist dein bearbeitetes Bild.",
                               artifacts: AnswerArtifacts(outImages: [Attachment(file: "img_bw.jpg")]),
                               model: "bild"),
                   to: store, convID: convID, started: started)
        let bubbles = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(bubbles.count, 1, "die Kette bekommt eine Blase, nicht drei")
        let only = try XCTUnwrap(bubbles.first)
        XCTAssertEqual(only.outImages?.count, 1,
                       "ein erzeugtes Bild darf nicht zweimal in derselben Blase stehen")
        XCTAssertEqual(only.gallery?.pictures.count, 1)
        XCTAssertTrue(only.text.contains("Schauspielerin"))
        XCTAssertTrue(only.text.contains("bearbeitetes Bild"))
    }

    func testSpeechOnlyHearsWhatIsNew() {
        let store = store()
        let convID = store.currentID!
        let writer = ChainMessageWriter()
        let slot = AnswerSlot(writer: writer)
        slot.store(AnswerPiece(text: "erster Teil."), to: store, convID: convID, started: Date())
        var spoken: [String] = []
        writer.speakNext { spoken.append($0) }
        slot.store(AnswerPiece(text: "zweiter Teil."), to: store, convID: convID, started: Date())
        writer.speakNext { spoken.append($0) }
        writer.speakNext { spoken.append($0) }
        XCTAssertEqual(spoken, ["erster Teil.", "zweiter Teil."],
                       "Vorlesen wiederholt nicht, was die Kette schon gesagt hat")
    }

    func testRemindersAtOnePlaceMergeTheirNotes() throws {
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Milch","location":"REWE","notes":"erste Notiz"}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Brot","location":"REWE","notes":"zweite Notiz"}"#))
        let plan = SendPlan.forming([first, second])
        XCTAssertEqual(plan.actions.count, 1)
        guard case .reminder(let merged)? = plan.actions.first?.route else { return XCTFail("kein Reminder") }
        XCTAssertTrue(merged.notes?.contains("erste Notiz") ?? false, merged.notes ?? "")
        XCTAssertTrue(merged.notes?.contains("zweite Notiz") ?? false, merged.notes ?? "")
    }

    func testReminderMergingLooksPastOtherSteps() throws {
        let chat = ToolDecision(route: .chat)
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Milch","location":"REWE"}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Brot","location":"REWE"}"#))
        let plan = SendPlan.forming([chat, first, second])
        XCTAssertEqual(plan.actions.filter { $0.stepKind == .reminder }.count, 1)
    }

    func testTwoNamedRemindersStayTwo() throws {
        var first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Arbeit"}"#))
        first.wish = "Erstelle eine Erinnerung mit dem Namen Arbeit"
        var second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
            arguments: #"{"action":"create","title":"Sport"}"#))
        second.wish = "Erstelle eine Erinnerung mit dem Namen Sport"
        let plan = SendPlan.forming([first, second])
        XCTAssertEqual(plan.actions.filter { $0.stepKind == .reminder }.count, 2,
                       "zwei eigenständig benannte Erinnerungen werden nicht gefaltet")
    }

    @MainActor
    func testACarryWithoutAnythingKeepsTheStep() async {
        let routed = RoutedSend(text: "frage", plan: .singleChat,
                                turn: ModelTurn(messages: [], images: []), history: [],
                                attachments: [], files: [], convID: UUID(), started: Date())
        let same = await routed.continuing(with: AnswerCarry(), since: 0, media: scratchMediaStore())
        XCTAssertEqual(same.text, "frage")
        XCTAssertTrue(same.history.isEmpty)
    }
}
