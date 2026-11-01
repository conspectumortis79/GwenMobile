@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import MessageUI
import XCTest
import GwenMobileKit

private struct MessageContacts: ContactDirectory {
    var granted = true
    var broken = false
    var stored: [ContactCard] = []

    func access() async -> ContactAccess { granted ? .granted : .denied }

    func cards() async throws -> [ContactCard] {
        if broken { throw APIError(message: "adressbuch gesperrt") }
        return stored
    }
}

@MainActor
private final class RecordingSender: MessageSending {
    private(set) var sent: [(text: String, number: DialNumber)] = []
    private let answer: MessageSendResult
    let way: String

    init(_ answer: MessageSendResult = .sent(direct: true), way: String = "aufnahme") {
        self.answer = answer
        self.way = way
    }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        sent.append((text, number))
        return answer
    }
}

final class MessageRoutingTests: GwenTestCase {
    private func messageFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.messageTool)
    }

    private func decision(_ arguments: String) -> ToolDecision? {
        ToolRouter.map(name: ToolRouter.messageTool, arguments: arguments)
    }

    func testTheMessageToolAsksForRecipientAndText() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.messageTool))
        let parameters = try XCTUnwrap(try messageFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["person", "text"])
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.keys.sorted(), ["group", "person", "relation", "text"])
    }

    func testTheDescriptionKeepsMailOtherAppsAndCallsAway() throws {
        let description = try XCTUnwrap(try messageFunction()["description"] as? String)
        XCTAssertTrue(description.contains("never from these examples"), description)
        XCTAssertTrue(description.contains(ToolRouter.callTool), description)
        XCTAssertTrue(description.contains("WhatsApp"), description)
        let parameters = try XCTUnwrap(try messageFunction()["parameters"] as? [String: Any])
        let text = (parameters["properties"] as? [String: Any])?["text"] as? [String: Any]
        XCTAssertTrue((text?["description"] as? String)?.contains("never translate it") ?? false,
                      "eine englische Nachricht kam auf dem iPhone übersetzt an")
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(system.contains("Use \(ToolRouter.messageTool) whenever"), system)
    }

    func testAMessageWishBecomesItsOwnRouteToAMobileNumber() {
        let made = decision(#"{"person":"Mutter","group":"Familie","relation":"mother","text":"Ich komme später."}"#)
        XCTAssertEqual(made?.route, .message(MessageRequest(recipient: ContactRequest(person: "Mutter", group: "Familie",
                                                                                      relation: .mother,
                                                                                      numberKind: .mobile),
                                                           text: "Ich komme später.")))
        XCTAssertEqual(made?.stepKind, .message)
    }

    func testWithoutRecipientThereIsNoMessageAndWithoutTextTheAppAsksLater() {
        XCTAssertEqual(decision(#"{"text":"Hallo"}"#)?.route, .chat)
        XCTAssertEqual(decision(#"{"person":"Peter"}"#)?.route,
                       .message(MessageRequest(recipient: ContactRequest(person: "Peter", numberKind: .mobile), text: "")))
    }

    func testAMessageRunsBeforeMusicAndCall() {
        let plan = SendPlan.forming([ToolDecision(route: .call(ContactRequest(person: "Papa"))),
                                     ToolDecision(route: .music(MusicRequest(action: .pause))),
                                     ToolDecision(route: .message(MessageRequest(recipient: ContactRequest(person: "Mama"),
                                                                                 text: "Hallo"))),
                                     ToolDecision(route: .chat)])
        XCTAssertEqual(plan.traceLine, "chat+message+music+call")
    }

    func testTheSplitterKnowsAMessageIsAWishOfItsOwn() {
        XCTAssertTrue(WishSplitter.system().contains("send one message to one person"), WishSplitter.system())
    }
}

@MainActor
final class MessageFlowRunnerTests: GwenTestCase {
    private let mother = ContactCard(id: "mutter", name: "Maria Muster", nameParts: ["Maria", "Muster"],
                                     groups: ["Familie"],
                                     phones: [ContactPhone(kind: .home, label: "Privat", number: "030 1111111"),
                                              ContactPhone(kind: .mobile, label: "Mobil", number: "+49 170 2222222")])

    private func request(_ text: String, person: String = "Maria Muster", group: String? = nil) -> MessageRequest {
        MessageRequest(recipient: ContactRequest(person: person, group: group, numberKind: .mobile), text: text)
    }

    private func run(_ request: MessageRequest, contacts: MessageContacts,
                     sender: RecordingSender) async -> MessageFlowOutcome {
        await MessageFlowRunner(directory: contacts, sender: sender, reviewer: RecordingSender(way: "pruefung"))
            .run(request)
    }

    func testAUniqueContactGetsTheTextOnTheMobileNumberExactlyOnce() async {
        let sender = RecordingSender(.sent(direct: true))
        let outcome = await run(request(" Ich komme später. "), contacts: MessageContacts(stored: [mother]), sender: sender)
        XCTAssertEqual(sender.sent.map(\.number), [DialNumber("+491702222222")!])
        XCTAssertEqual(sender.sent.map(\.text), ["Ich komme später."])
        XCTAssertEqual(outcome.text, "✉️ Text message sent to Maria Muster · Mobil: “Ich komme später.”")
        XCTAssertFalse(outcome.trace.contains("später"), "der Nachrichtentext gehört nicht in die Spur")
    }

    func testADoubtfulTextGoesToTheFormForReviewInsteadOfStraightOut() async {
        let direct = RecordingSender(.sent(direct: true), way: "direkt")
        let form = RecordingSender(.sent(direct: false), way: "formular")
        var doubtful = request("Ich liebe dich.")
        doubtful.needsReview = true
        let outcome = await MessageFlowRunner(directory: MessageContacts(stored: [mother]), sender: direct,
                                              reviewer: form).run(doubtful)
        XCTAssertTrue(direct.sent.isEmpty, "ein zweifelhafter Text geht nie ungesehen hinaus")
        XCTAssertEqual(form.sent.map(\.text), ["Ich liebe dich."])
        XCTAssertTrue(outcome.trace.contains("pruefen=true"), outcome.trace)
    }

    func testTheFormAnswerSaysTheMessageWasSentByThePerson() async {
        let outcome = await run(request("Hallo"), contacts: MessageContacts(stored: [mother]),
                                sender: RecordingSender(.sent(direct: false)))
        XCTAssertEqual(outcome.text, "✉️ Message sent to Maria Muster · Mobil: “Hallo”")
    }

    func testWithoutTextNothingIsLookedUpOrSent() async {
        let sender = RecordingSender()
        let outcome = await run(request("  "), contacts: MessageContacts(granted: false), sender: sender)
        XCTAssertEqual(outcome.text, "What should I write to Maria Muster? Tell me once more together with the text.")
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func testDeniedOrBrokenContactsNeverSend() async {
        let sender = RecordingSender()
        let denied = await run(request("Hallo"), contacts: MessageContacts(granted: false), sender: sender)
        XCTAssertEqual(denied.text, L.t("contact_denied"))
        let broken = await run(request("Hallo"), contacts: MessageContacts(broken: true), sender: sender)
        XCTAssertEqual(broken.text, L.t("contact_unreadable"))
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func testTwoFittingContactsAreAskedBackInsteadOfWrittenTo() async {
        let twin = ContactCard(id: "zwei", name: "Maria Musterfrau", nameParts: ["Maria", "Musterfrau"],
                               phones: [ContactPhone(kind: .mobile, label: "Mobil", number: "0170 3")])
        let sender = RecordingSender()
        let outcome = await run(request("Hallo", person: "Maria"), contacts: MessageContacts(stored: [mother, twin]),
                                sender: sender)
        XCTAssertEqual(outcome.text, "Several contacts fit: Maria Muster, Maria Musterfrau. Tell me whom to write to.")
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func testEveryResultOfTheSenderIsExplained() async {
        let contacts = MessageContacts(stored: [mother])
        let cancelled = await run(request("Hallo"), contacts: contacts, sender: RecordingSender(.cancelled))
        XCTAssertEqual(cancelled.text, "The message to Maria Muster was not sent.")
        let away = await run(request("Hallo"), contacts: contacts, sender: RecordingSender(.needsForeground))
        XCTAssertTrue(away.text.contains("foreground"), away.text)
        let failed = await run(request("Hallo"), contacts: contacts, sender: RecordingSender(.failed("kein Netz")))
        XCTAssertEqual(failed.text, "The message to Maria Muster could not be sent: kein Netz")
        let unable = await run(request("Hallo"), contacts: contacts, sender: RecordingSender(.unavailable))
        XCTAssertEqual(unable.text, L.t("message_unavailable"))
    }

    func testTheGroupNoteFollowsTheSentLine() async {
        let outcome = await run(request("Hallo", group: "Verein"), contacts: MessageContacts(stored: [mother]),
                                sender: RecordingSender())
        XCTAssertEqual(outcome.text.components(separatedBy: "\n").last, L.fmt("contact_group_missing", "Verein"))
    }

    func testTheCarrierIsOnlyReplacedWhenItIsNotSetUpNeverAfterAFailure() async {
        let number = DialNumber("0170 1")!
        let notSetUp = RecordingSender(.unavailable, way: "mobilfunk")
        let form = RecordingSender(.sent(direct: false), way: "formular")
        let rescued = await FallbackMessageSender(first: notSetUp, then: form).send("Hallo", to: number)
        XCTAssertEqual(rescued, .sent(direct: false))
        XCTAssertEqual(form.sent.count, 1)
        let broken = RecordingSender(.failed("x"), way: "mobilfunk")
        let unused = RecordingSender(.sent(direct: false), way: "formular")
        let failed = await FallbackMessageSender(first: broken, then: unused).send("Hallo", to: number)
        XCTAssertEqual(failed, .failed("x"))
        XCTAssertTrue(unused.sent.isEmpty, "eine fehlgeschlagene SMS darf nie ein zweites Mal hinausgehen")
    }

    func testWithoutTheEntitlementOnlyTheFormIsUsed() {
        let plain = MessagingChoice.sender(for: MessagingCapability(entitled: false, carrierAvailable: true),
                                           carrier: { RecordingSender(way: "mobilfunk") },
                                           compose: { RecordingSender(way: "formular") })
        XCTAssertEqual(plain.way, "formular")
        let direct = MessagingChoice.sender(for: MessagingCapability(entitled: true, carrierAvailable: true),
                                            carrier: { RecordingSender(way: "mobilfunk") },
                                            compose: { RecordingSender(way: "formular") })
        XCTAssertEqual(direct.way, "mobilfunk>formular")
        XCTAssertFalse(MessagingCapability(entitled: true, carrierAvailable: false).direct)
    }

    func testThisBuildCarriesTheMessagingFlagAndIsNotEntitled() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: MessagingChoice.infoKey) as? String)
        XCTAssertFalse(MessagingChoice.capability(bundle: .main, carrierAvailable: true).entitled,
                       "ohne GWEN_MESSAGING bleibt es beim Nachrichtenformular")
    }

    func testTheFormIsNeverShownWhereItCannotWork() async {
        let unable = ComposeMessageSender(canSend: { false }, isActive: { true }, host: { nil })
        let first = await unable.send("Hallo", to: DialNumber("0170 1")!)
        XCTAssertEqual(first, .unavailable)
        let away = ComposeMessageSender(canSend: { true }, isActive: { false }, host: { nil })
        let second = await away.send("Hallo", to: DialNumber("0170 1")!)
        XCTAssertEqual(second, .needsForeground)
    }

    func testTheFormResultIsTranslated() {
        XCTAssertEqual(ComposeMessageSender.result(of: .sent), .sent(direct: false))
        XCTAssertEqual(ComposeMessageSender.result(of: .cancelled), .cancelled)
        XCTAssertEqual(ComposeMessageSender.result(of: .failed), .failed(L.t("message_compose_failed")))
    }

    func testTheSharedLookupReportsAccessReadingAndResolution() async {
        let denied = await ContactLookup(directory: MessageContacts(granted: false)).resolve(ContactRequest(person: "Maria"))
        XCTAssertEqual(denied, .denied)
        let resolved = await ContactLookup(directory: MessageContacts(stored: [mother]))
            .resolve(ContactRequest(person: "Maria Muster"))
        guard case .resolved(.unique(let target, _), 1) = resolved else { return XCTFail("\(resolved)") }
        XCTAssertEqual(target.name, "Maria Muster")
        XCTAssertTrue(BuildFlag.isOn("YES"))
        XCTAssertFalse(BuildFlag.isOn(MessagingChoice.infoKey, in: .main))
    }
}

final class MessageLanguageCheckTests: XCTestCase {
    private func message(_ text: String) -> ToolDecision {
        ToolDecision(route: .message(MessageRequest(recipient: ContactRequest(person: "sister"), text: text)),
                     wish: "eigener Wunsch")
    }

    func testATranslatedMessageIsNoticedAndAMatchingOneIsNot() {
        let english = "Text my sister that I love her and that I will visit her on Sunday"
        XCTAssertTrue(MessageLanguageCheck.translated(message("Ich liebe dich und besuche dich am Sonntag."),
                                                      wish: english))
        XCTAssertFalse(MessageLanguageCheck.translated(message("I love you and I will visit you on Sunday."),
                                                       wish: english))
        XCTAssertFalse(MessageLanguageCheck.translated(ToolDecision(route: .chat), wish: english))
    }

    func testTooShortToJudgeIsNeverAskedAgain() {
        XCTAssertNil(SpokenLanguage.of("OK"))
        XCTAssertFalse(MessageLanguageCheck.translated(message("OK"), wish: "Text Tom OK"))
    }

    func testATranslationIsAskedAgainOnceAndKeepsItsWish() async {
        var hints: [String] = []
        let fixed = ToolDecision(route: .message(MessageRequest(recipient: ContactRequest(person: "sister"),
                                                                text: "I love you and I will visit you on Sunday.")))
        let result = await MessageLanguageCheck().checked(message("Ich liebe dich und besuche dich am Sonntag."),
                                                          wish: "Text my sister that I love her and that I will visit her on Sunday") { hint in
            hints.append(hint)
            return fixed
        }
        XCTAssertEqual(hints, [MessageLanguageCheck.hint(for: .english)])
        XCTAssertTrue(hints.first?.contains("The user wrote in English") ?? false, hints.first ?? "")
        XCTAssertEqual(result.route, fixed.route)
        XCTAssertEqual(result.wish, "eigener Wunsch")
    }

    func testAMatchingMessageIsNeverAskedAgainAndAnOffTopicAnswerIsIgnored() async {
        var asked = 0
        let same = message("I love you and I will visit you on Sunday.")
        let kept = await MessageLanguageCheck().checked(same, wish: "Text my sister that I love her and that I will visit her on Sunday") { _ in
            asked += 1
            return nil
        }
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(kept, same)
        let translated = message("Ich liebe dich und besuche dich am Sonntag.")
        let stayed = await MessageLanguageCheck().checked(translated, wish: "Text my sister that I love her and that I will visit her on Sunday") { _ in
            ToolDecision(route: .chat)
        }
        XCTAssertEqual(stayed, translated, "eine Antwort ohne Nachricht ersetzt die Nachricht nicht")
    }

    func testAStubbornTranslationIsMarkedForReview() async {
        let wish = "Text my sister that I love her and that I will visit her on Sunday"
        let result = await MessageLanguageCheck().checked(message("Ich liebe dich und besuche dich am Sonntag."),
                                                          wish: wish) { _ in
            self.message("Ich liebe dich und besuche dich am Sonntag.")
        }
        guard case .message(let request) = result.route else { return XCTFail("\(result.route)") }
        XCTAssertTrue(request.needsReview)
    }

    func testTheRouterRunsThePlaceAndTheLanguageCheck() {
        XCTAssertTrue(ToolRouter.confirmations.contains { $0 is NearbyWishCheck })
        XCTAssertTrue(ToolRouter.confirmations.contains { $0 is MessageLanguageCheck })
    }
}
