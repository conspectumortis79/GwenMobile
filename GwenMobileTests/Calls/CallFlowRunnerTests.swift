@testable import GwenMobileFeatureCore
import Contacts
import XCTest
import GwenMobileKit

private struct StubContacts: ContactDirectory {
    var granted = true
    var stored: [ContactCard] = []
    var broken = false

    func access() async -> ContactAccess { granted ? .granted : .denied }

    func cards() async throws -> [ContactCard] {
        if broken { throw APIError(message: "adressbuch gesperrt") }
        return stored
    }
}

@MainActor
private final class RecordingDialer: CallPlacing {
    private(set) var numbers: [DialNumber] = []
    private let answer: CallStart
    let way: String

    init(_ answer: CallStart = .dialing, way: String = "aufnahme") {
        self.answer = answer
        self.way = way
    }

    func place(_ number: DialNumber) async -> CallStart {
        numbers.append(number)
        return answer
    }
}

@MainActor
private final class RecordingOpener: URLOpening {
    private(set) var urls: [URL] = []
    private let answer: Bool

    init(_ answer: Bool) {
        self.answer = answer
    }

    func open(_ url: URL) async -> Bool {
        urls.append(url)
        return answer
    }
}

@MainActor
final class CallFlowRunnerTests: GwenTestCase {
    private let mother = ContactCard(id: "mutter", name: "Maria Muster", nameParts: ["Maria", "Muster"],
                                     groups: ["Familie"],
                                     phones: [ContactPhone(kind: .mobile, label: "Mobil", number: "+49 170 2222222")])
    private let request = ContactRequest(person: "Maria Muster")

    private func run(_ request: ContactRequest, contacts: StubContacts,
                     dialer: RecordingDialer) async -> CallFlowOutcome {
        await CallFlowRunner(directory: contacts, dialer: dialer).run(request)
    }

    func testAUniqueContactIsDialledExactlyOnce() async {
        let dialer = RecordingDialer(.dialing)
        let outcome = await run(request, contacts: StubContacts(stored: [mother]), dialer: dialer)
        XCTAssertEqual(dialer.numbers, [DialNumber("+491702222222")!])
        XCTAssertEqual(outcome.text, "📞 Calling Maria Muster · Mobil.")
        XCTAssertTrue(outcome.placed)
    }

    func testTheConfirmingPathNamesTheButtonThatIsLeft() async {
        let outcome = await run(request, contacts: StubContacts(stored: [mother]), dialer: RecordingDialer(.confirming))
        XCTAssertTrue(outcome.text.contains("“Call”"), outcome.text)
        XCTAssertTrue(outcome.placed)
    }

    func testAFailedStartIsReportedAndCountsAsNotPlaced() async {
        let outcome = await run(request, contacts: StubContacts(stored: [mother]), dialer: RecordingDialer(.failed))
        XCTAssertEqual(outcome.text, L.fmt("call_failed", "Maria Muster"))
        XCTAssertFalse(outcome.placed, "ein gescheiterter Start wird vorgelesen")
    }

    func testDeniedAccessNeverReadsOrDials() async {
        let dialer = RecordingDialer()
        let outcome = await run(request, contacts: StubContacts(granted: false, stored: [mother]), dialer: dialer)
        XCTAssertEqual(outcome.text, L.t("contact_denied"))
        XCTAssertTrue(dialer.numbers.isEmpty)
        XCTAssertFalse(outcome.placed)
    }

    func testAnUnreadableAddressBookNeverDials() async {
        let dialer = RecordingDialer()
        let outcome = await run(request, contacts: StubContacts(broken: true), dialer: dialer)
        XCTAssertEqual(outcome.text, L.t("contact_unreadable"))
        XCTAssertTrue(dialer.numbers.isEmpty)
    }

    func testSeveralContactsAreListedAndNobodyIsDialled() async {
        let twin = ContactCard(id: "zwei", name: "Maria Musterfrau", nameParts: ["Maria", "Musterfrau"],
                               phones: [ContactPhone(kind: .mobile, label: "Mobil", number: "0170 3")])
        let dialer = RecordingDialer()
        let outcome = await run(ContactRequest(person: "Maria"), contacts: StubContacts(stored: [mother, twin]),
                                dialer: dialer)
        XCTAssertTrue(dialer.numbers.isEmpty)
        XCTAssertEqual(outcome.text, L.fmt("call_ambiguous", "Maria Muster, Maria Musterfrau"))
    }

    func testASimilarNameIsOnlyAskedBack() async {
        let dialer = RecordingDialer()
        let outcome = await run(ContactRequest(person: "Marla Muster"), contacts: StubContacts(stored: [mother]),
                                dialer: dialer)
        XCTAssertTrue(dialer.numbers.isEmpty, "ein ähnlich klingender Name wird nie ungefragt gewählt")
        XCTAssertEqual(outcome.text, L.fmt("contact_unsure", "Maria Muster"))
    }

    func testAnUnknownPersonIsNamedInTheAnswer() async {
        let outcome = await run(ContactRequest(person: "Zacharias"), contacts: StubContacts(stored: [mother]),
                                dialer: RecordingDialer())
        XCTAssertEqual(outcome.text, "I found no contact for “Zacharias”.")
    }

    func testTheGroupNoteFollowsTheCallLine() async {
        let outcome = await run(ContactRequest(person: "Maria Muster", group: "Verein"),
                                contacts: StubContacts(stored: [mother]), dialer: RecordingDialer())
        XCTAssertEqual(outcome.text.components(separatedBy: "\n"),
                       ["📞 Calling Maria Muster · Mobil.", L.fmt("contact_group_missing", "Verein")])
    }

    func testTheTraceNeverCarriesTheWholeNumber() async {
        let outcome = await run(request, contacts: StubContacts(stored: [mother]), dialer: RecordingDialer())
        XCTAssertFalse(outcome.trace.contains("1702222222"), outcome.trace)
        XCTAssertTrue(outcome.trace.contains("weg=aufnahme"), outcome.trace)
    }

    func testThePhoneLinkHandsTheTelURLToTheSystemAndLeavesTheConfirmationToIt() async {
        let opener = RecordingOpener(true)
        let started = await PhoneLinkDialer(opener: opener).place(DialNumber("+49 170 2222222")!)
        XCTAssertEqual(started, .confirming)
        XCTAssertEqual(opener.urls.map(\.absoluteString), ["tel:+491702222222"])
        let refused = await PhoneLinkDialer(opener: RecordingOpener(false)).place(DialNumber("0170 1")!)
        XCTAssertEqual(refused, .failed)
    }

    func testTheSecondWayOnlyStepsInWhenTheFirstFails() async {
        let broken = RecordingDialer(.failed, way: "erst")
        let spare = RecordingDialer(.confirming, way: "dann")
        let number = DialNumber("0170 1")!
        let rescued = await FallbackDialer(first: broken, then: spare).place(number)
        XCTAssertEqual(rescued, .confirming)
        XCTAssertEqual(spare.numbers, [number])
        let working = RecordingDialer(.dialing, way: "erst")
        let unused = RecordingDialer(.confirming, way: "dann")
        let direct = await FallbackDialer(first: working, then: unused).place(number)
        XCTAssertEqual(direct, .dialing)
        XCTAssertTrue(unused.numbers.isEmpty, "wer schon wählt, bekommt keinen zweiten Anruf hinterher")
        XCTAssertEqual(FallbackDialer(first: working, then: unused).way, "erst>dann")
    }

    func testWithoutTheEntitlementTheCellularWayIsNeverTried() {
        let link = RecordingDialer(way: "link")
        var asked = 0
        let chosen = DialerChoice.dialer(for: DialerCapability(entitled: false, cellularAvailable: true),
                                         cellular: { asked += 1; return RecordingDialer(way: "mobil") }, link: link)
        XCTAssertEqual(chosen.way, "link")
        XCTAssertEqual(asked, 0)
        let freed = DialerChoice.dialer(for: DialerCapability(entitled: true, cellularAvailable: true),
                                        cellular: { RecordingDialer(way: "mobil") }, link: link)
        XCTAssertEqual(freed.way, "mobil>link")
        let old = DialerChoice.dialer(for: DialerCapability(entitled: true, cellularAvailable: false),
                                      cellular: { nil }, link: link)
        XCTAssertEqual(old.way, "link")
    }

    func testHandsFreeNeedsTheEntitlementAndTheCellularInterface() {
        XCTAssertTrue(DialerCapability(entitled: true, cellularAvailable: true).handsFree)
        XCTAssertFalse(DialerCapability(entitled: true, cellularAvailable: false).handsFree)
        XCTAssertFalse(DialerCapability(entitled: false, cellularAvailable: true).handsFree)
    }

    func testTheBuildFlagIsReadStrictly() {
        for yes: Any in ["YES", "yes", " 1 ", "true", true] {
            XCTAssertTrue(BuildFlag.isOn(yes), "\(yes)")
        }
        for no: Any in ["", "NO", "$(GWEN_DIALER)", false] {
            XCTAssertFalse(BuildFlag.isOn(no), "\(no)")
        }
        XCTAssertFalse(BuildFlag.isOn(nil))
    }

    func testThisBuildCarriesTheFlagAndIsNotEntitled() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: DialerChoice.infoKey) as? String,
                        "Info.plist muss den Schalter tragen")
        XCTAssertFalse(DialerChoice.capability(bundle: .main, cellularAvailable: true).entitled,
                       "ohne GWEN_DIALER bleibt der Build beim Weg mit iOS-Rückfrage")
    }

    func testTheDeskSwapsInAProbeDialerAndRestoresTheLiveOne() {
        let live = RecordingDialer(way: "live")
        let desk = CallDesk(directory: StubContacts(), dialer: live)
        desk.stand(in: RecordingDialer(way: "probe"))
        desk.stand(in: RecordingDialer(way: "probe2"), directory: StubContacts(granted: false))
        XCTAssertEqual(desk.dialer.way, "probe2")
        desk.restore()
        XCTAssertEqual(desk.dialer.way, "live", "nach der Probe wählt wieder der echte Weg")
        desk.restore()
        XCTAssertEqual(desk.dialer.way, "live")
    }

    func testTheAddressBookEntryIsReadIntoACard() {
        let contact = CNMutableContact()
        contact.givenName = "Maria"
        contact.familyName = "Muster"
        contact.nickname = "Mama"
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+49 170 2222222")),
            CNLabeledValue(label: CNLabelPhoneNumberHomeFax, value: CNPhoneNumber(stringValue: "+49 30 9")),
            CNLabeledValue(label: "Garten", value: CNPhoneNumber(stringValue: "0170 8")),
        ]
        contact.contactRelations = [
            CNLabeledValue(label: CNLabelContactRelationMother, value: CNContactRelation(name: "Oma Hilde")),
        ]
        let card = ContactCardMapper.card(from: contact, groups: ["Familie"])
        XCTAssertEqual(card.nameParts, ["Maria", "Muster", "Mama"])
        XCTAssertFalse(card.name.isEmpty)
        XCTAssertEqual(card.groups, ["Familie"])
        XCTAssertEqual(card.phones.map(\.kind), [.mobile, .other], "ein Fax wird nie angerufen")
        XCTAssertEqual(card.phones.last?.label, "Garten")
        XCTAssertEqual(card.ties.first?.relation, .mother)
        XCTAssertEqual(card.ties.first?.name, "Oma Hilde")
        XCTAssertFalse(card.ties.first?.label.contains("_$!<") ?? true, "das Etikett kommt übersetzt an")
    }
}
