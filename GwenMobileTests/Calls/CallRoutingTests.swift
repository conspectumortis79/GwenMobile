@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CallRoutingTests: GwenTestCase {
    private func callFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.callTool)
    }

    private func decision(_ arguments: String) -> ToolDecision? {
        ToolRouter.map(name: ToolRouter.callTool, arguments: arguments)
    }

    func testTheCallToolIsOfferedWithAndWithoutAPicture() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.callTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.callTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true, translatesOnDevice: false)).contains(ToolRouter.callTool))
    }

    func testTheCallToolAsksForThePersonAndOffersClosedLists() throws {
        let parameters = try XCTUnwrap(try callFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["person"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(), ["group", "number", "person", "relation"])
        XCTAssertEqual((properties["relation"] as? [String: Any])?["enum"] as? [String], ContactRelation.toolValues)
        XCTAssertEqual((properties["number"] as? [String: Any])?["enum"] as? [String], PhoneKind.toolValues)
        XCTAssertTrue(ContactRelation.toolValues.contains(ContactRelation.noneValue))
        XCTAssertTrue(PhoneKind.toolValues.contains(PhoneKind.anyValue))
        XCTAssertFalse(PhoneKind.toolValues.contains(PhoneKind.other.rawValue))
    }

    func testTheDescriptionKeepsQuestionsAboutCallsAndCodeAway() throws {
        let description = try XCTUnwrap(try callFunction()["description"] as? String)
        XCTAssertTrue(description.contains("answer_in_chat or search_web"), description)
        XCTAssertTrue(description.contains(ToolRouter.codeTool), description)
        XCTAssertTrue(description.contains("Family: Mother"), description)
    }

    func testTheExamplesCarryNoRelationTheModelCouldCopyIntoAnotherCall() throws {
        let description = try XCTUnwrap(try callFunction()["description"] as? String)
        XCTAssertTrue(description.contains("never from these examples"), description)
        for copied in ["brother", "sister", "his mobile", "her mobile"] {
            XCTAssertFalse(description.contains(copied),
                           "\(copied): ein Beispiel wurde auf dem iPhone statt der Worte des Nutzers übernommen")
        }
    }

    func testTheRouterPolicyNamesTheCallTool() {
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(system.contains("Use \(ToolRouter.callTool) only when"), system)
    }

    func testAFamilyCallBecomesItsOwnRouteWithEveryField() throws {
        let made = try XCTUnwrap(decision(#"{"person":"Mutter","group":"Familie","relation":"mother","number":"mobile"}"#))
        XCTAssertEqual(made.route, .call(ContactRequest(person: "Mutter", group: "Familie", relation: .mother,
                                                     numberKind: .mobile)))
        XCTAssertEqual(made.stepKind, .call)
    }

    func testNoneAnyAndUnknownValuesStayOpen() throws {
        let plain = ContactRequest(person: "Peter")
        XCTAssertEqual(decision(#"{"person":"Peter","group":"","relation":"none","number":"any"}"#)?.route,
                       .call(plain))
        XCTAssertEqual(decision(#"{"person":"Peter","relation":"nachbar","number":"fax"}"#)?.route, .call(plain))
        XCTAssertEqual(decision(#"{"person":"Peter","number":"other"}"#)?.route, .call(plain),
                       "other ist keine Wahl des Modells")
        XCTAssertEqual(decision(#"{"person":"Peter","relation":" Mother "}"#)?.route,
                       .call(ContactRequest(person: "Peter", relation: .mother)))
    }

    func testACallWithoutAnybodyToCallFallsBackToChat() {
        XCTAssertEqual(decision(#"{"person":"  "}"#)?.route, .chat)
        XCTAssertEqual(decision("kein json")?.route, .chat)
    }

    func testARelationAloneIsEnoughToCall() {
        XCTAssertEqual(decision(#"{"person":"","relation":"father"}"#)?.route,
                       .call(ContactRequest(person: "", relation: .father)))
    }

    func testTheModelAnswerBecomesACallPlan() {
        let data = payload(ToolRouter.callTool, #"{"person":"Mama","relation":"mother"}"#)
        XCTAssertEqual(SendPlan.forming(ToolRouter.decisions(from: data)).primary.route,
                       .call(ContactRequest(person: "Mama", relation: .mother)))
    }

    func testACallRunsLastAndOnlyOnceInAMessage() {
        let mother = ToolDecision(route: .call(ContactRequest(person: "Mama", relation: .mother)))
        let father = ToolDecision(route: .call(ContactRequest(person: "Papa", relation: .father)))
        let plan = SendPlan.forming([mother, ToolDecision(route: .pictureSearch(query: "katzen")), father])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.gallery, .call],
                       "erst die übrigen Wünsche, dann genau ein Anruf")
        XCTAssertEqual(plan.actions.last?.route, mother.route)
    }

    func testTheOtherStepsKeepTheirOrderBeforeTheCall() {
        let plan = SendPlan.forming([ToolDecision(route: .call(ContactRequest(person: "Mama"))),
                                     ToolDecision(route: .chat),
                                     ToolDecision(route: .nearbyPlace(terms: ["apotheke"], mode: .walking))])
        XCTAssertEqual(plan.traceLine, "chat+place+call")
    }

    func testAChainWithACallNeverMergesSoNothingIsReadAloudOverTheRinging() {
        let plan = SendPlan.forming([ToolDecision(route: .chat),
                                     ToolDecision(route: .call(ContactRequest(person: "Mama")))])
        XCTAssertFalse(plan.merges)
    }

    func testTheStepKeyCarriesWhoIsCalled() {
        let mother = ToolDecision(route: .call(ContactRequest(person: "Mama", relation: .mother)))
        XCTAssertEqual(mother.stepKey, "call|mama mother")
        XCTAssertEqual(mother.stepDetail, "Mama mother")
    }

    func testTheSplitterKnowsThatACallIsAWishOfItsOwn() {
        XCTAssertTrue(WishSplitter.system().contains("phone one person"), WishSplitter.system())
    }

    func testTheAnswerPromptNeverDeniesPhoneCalls() {
        XCTAssertTrue(L.strings["picture_honesty_prompt"]?[.de]?.contains("keine Anrufe") ?? false)
        XCTAssertTrue(L.strings["picture_honesty_prompt"]?[.en]?.contains("cannot place phone calls") ?? false)
    }

    func testRelationsCoverOnlyTheirOwnNarrowerKinds() {
        XCTAssertTrue(ContactRelation.parent.covers(.mother))
        XCTAssertTrue(ContactRelation.parent.covers(.father))
        XCTAssertTrue(ContactRelation.spouse.covers(.wife))
        XCTAssertTrue(ContactRelation.mother.covers(.mother))
        XCTAssertFalse(ContactRelation.mother.covers(.parent), "ein Elternteil ohne Geschlecht ist nicht die Mutter")
        XCTAssertFalse(ContactRelation.sister.covers(.brother))
    }
}
