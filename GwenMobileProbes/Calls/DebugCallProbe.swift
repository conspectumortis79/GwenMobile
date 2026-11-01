@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import UIKit

@MainActor
final class ProbeDialer: CallPlacing {
    private(set) var numbers: [DialNumber] = []
    private let answer: CallStart

    init(answer: CallStart = .dialing) {
        self.answer = answer
    }

    var way: String { "probe_ohne_wahl" }

    func place(_ number: DialNumber) async -> CallStart {
        numbers.append(number)
        flowMark("ANRUF probe haelt die wahl zurueck nummer=\(number.masked)")
        return answer
    }
}

struct FixtureContacts: ContactDirectory {
    static let motherMobile = "+49 000 0000001"
    static let motherHome = "+49 000 0000002"
    static let firstPeter = "+49 000 0000003"
    static let secondPeter = "+49 000 0000004"

    static let cards: [ContactCard] = [
        ContactCard(id: "probe-ich", name: "Gwen Probeperson", nameParts: ["Gwen", "Probeperson"],
                    ties: [ContactTie(relation: .mother, label: "Mutter", name: "Maria Probemuster")]),
        ContactCard(id: "probe-mutter", name: "Maria Probemuster", nameParts: ["Maria", "Probemuster"],
                    groups: ["Familie"],
                    phones: [ContactPhone(kind: .home, label: "Privat", number: motherHome),
                             ContactPhone(kind: .mobile, label: "Mobil", number: motherMobile)]),
        ContactCard(id: "probe-peter-a", name: "Peter Alphaprobe", nameParts: ["Peter", "Alphaprobe"],
                    phones: [ContactPhone(kind: .mobile, label: "Mobil", number: firstPeter)]),
        ContactCard(id: "probe-peter-b", name: "Peter Betaprobe", nameParts: ["Peter", "Betaprobe"],
                    phones: [ContactPhone(kind: .mobile, label: "Mobil", number: secondPeter)]),
        ContactCard(id: "probe-otto", name: "Otto Ohnenummer", nameParts: ["Otto", "Ohnenummer"],
                    groups: ["Familie"]),
    ]

    func access() async -> ContactAccess { .granted }

    func cards() async throws -> [ContactCard] { Self.cards }
}

@MainActor
enum DebugCallProbe {
    private struct RouteCase {
        let text: String
        let wanted: SendStepKind
        var relation: ContactRelation?
        var group: String?
        var exact = true
    }

    private static let routeCases = [
        RouteCase(text: "Bitte rufe Familie: Mutter an", wanted: .call, relation: .mother, group: "Familie"),
        RouteCase(text: "Ruf Mama an", wanted: .call, relation: .mother),
        RouteCase(text: "Kannst du Peter Müller auf dem Handy anrufen?", wanted: .call),
        RouteCase(text: "Ruf meinen Bruder an", wanted: .call, relation: .brother),
        RouteCase(text: "Call my sister on her mobile", wanted: .call, relation: .sister),
        RouteCase(text: "Ruf die Pizzeria Roma an", wanted: .call),
        RouteCase(text: "Was kostet ein Anruf nach Italien?", wanted: .chat, exact: false),
        RouteCase(text: "Wie rufe ich in Italien die Polizei an?", wanted: .chat, exact: false),
        RouteCase(text: "Welche Telefonnummer hat das Rathaus Berlin?", wanted: .search, exact: false),
        RouteCase(text: "Schreib mir eine Python-Funktion, die eine REST-API aufruft", wanted: .code),
        RouteCase(text: "Zeig mir Bilder vom Eiffelturm", wanted: .gallery),
        RouteCase(text: "Wo ist die nächste Apotheke?", wanted: .place),
        RouteCase(text: "Route mich mit dem Fahrrad zur Stadtbibliothek", wanted: .route),
        RouteCase(text: "Trag morgen um 9 Uhr einen Termin Zahnarzt ein", wanted: .calendar),
    ]

    static func routing(_ view: ChatView) async {
        let wanted = routeCases.filter { $0.wanted == .call }.count
        var calls = 0
        var others = 0
        await RouteSweep.run(routeCases, file: "call_route.txt", view: view, log: "ANRUFROUTING fertig",
                             konfig: RouteSweep.konfig(view, routeCases.count,
                                                       extra: "waehlt=\(view.callDesk.dialer.way)"),
                             sentence: { $0.text },
                             fits: { fitting($0, kind: $1.primary.stepKind, request: contactRequest($1)) },
                             line: { item, plan, pass, ms in
                                 let request = contactRequest(plan)
                                 return "passt=\(pass) soll=\(item.wanted.rawValue) ist=\(plan.traceLine) "
                                     + "person=\(request?.person ?? "-") gruppe=\(request?.group ?? "-") "
                                     + "beziehung=\(request?.relation?.rawValue ?? "-") "
                                     + "nummer=\(request?.numberKind?.rawValue ?? "-") ms=\(ms) text=\(item.text)"
                             },
                             onResult: { item, pass in
                                 if item.wanted == .call { calls += pass ? 1 : 0 }
                                 else { others += pass ? 1 : 0 }
                             },
                             summe: { _ in
                                 "anrufe_erkannt=\(calls)/\(wanted) "
                                     + "uebrige_richtig=\(others)/\(routeCases.count - wanted)"
                             })
    }

    private static func contactRequest(_ plan: SendPlan) -> ContactRequest? {
        guard case .call(let request) = plan.primary.route else { return nil }
        return request
    }

    private static func fitting(_ item: RouteCase, kind: SendStepKind, request: ContactRequest?) -> Bool {
        if item.wanted == .call { return kind == .call && relationFits(item, request) }
        return item.exact ? kind == item.wanted : kind != .call
    }

    private static func relationFits(_ item: RouteCase, _ request: ContactRequest?) -> Bool {
        guard let request else { return false }
        if let relation = item.relation, request.relation != relation { return false }
        if let group = item.group {
            return TextFolding.fold(request.group ?? "").contains(TextFolding.fold(group))
        }
        return true
    }

    private static let flowCases = [
        FlowCase(text: "Bitte rufe Familie: Mutter an", number: FixtureContacts.motherMobile,
                 words: ["Maria Probemuster"]),
        FlowCase(text: "Ruf Maria Probemuster zu Hause an", number: FixtureContacts.motherHome,
                 words: ["Maria Probemuster"]),
        FlowCase(text: "Ruf Peter an", number: nil, words: ["Alphaprobe", "Betaprobe"]),
        FlowCase(text: "Ruf Otto Ohnenummer an", number: nil, words: ["Otto Ohnenummer"]),
        FlowCase(text: "Ruf Zacharias Unbekanntprobe an", number: nil, words: ["Zacharias"]),
        FlowCase(text: "Was kostet ein Anruf nach Italien?", number: nil, words: []),
    ]

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "call_flow.txt")
        let dialer = ProbeDialer()
        view.callDesk.stand(in: dialer, directory: FixtureContacts())
        report.add("KONFIG", "waehlt=\(view.callDesk.dialer.way) kontakte=\(FixtureContacts.cards.count)")
        var right = 0
        for (index, item) in flowCases.enumerated() {
            let before = dialer.numbers.count
            let answer = await view.ask(item.text, fresh: true)
            let dialed = Array(dialer.numbers.dropFirst(before))
            let expected = item.number.flatMap(DialNumber.init)
            let numberFits = expected.map { dialed == [$0] } ?? dialed.isEmpty
            let text = answer?.text ?? ""
            let wordsFit = item.words.allSatisfy { TextFolding.fold(text).contains(TextFolding.fold($0)) }
            right += numberFits && wordsFit ? 1 : 0
            report.add("FALL_\(index + 1)", "passt=\(numberFits && wordsFit) gewaehlt=\(dialed.map(\.masked)) "
                       + "soll=\(expected?.masked ?? "nichts") schritte=\(view.probeLastPlan?.traceLine ?? "-") "
                       + "antwort=\(TextLine.oneLine(text, limit: 160))")
        }
        report.add("SUMME", "richtig=\(right)/\(flowCases.count) gewaehlt_gesamt=\(dialer.numbers.count)")
        flowLog.info("ANRUFABLAUF fertig")
    }

    private struct LinkCase {
        let text: String
        let expected: [String]
    }

    private static let linkCases = [
        LinkCase(text: "Du erreichst Maria unter 0170 1234567.", expected: ["0170 1234567"]),
        LinkCase(text: "Die Zentrale: +49 30 12345678", expected: ["+49 30 12345678"]),
        LinkCase(text: "Mobil: +49 (0) 170 2222222", expected: ["+49 (0) 170 2222222"]),
        LinkCase(text: "Zwei Nummern: 030 123456 und 0170 2222222.", expected: ["030 123456", "0170 2222222"]),
        LinkCase(text: "Am 01.01.2024 ist es so weit.", expected: []),
        LinkCase(text: "Die PLZ ist 01067.", expected: []),
        LinkCase(text: "Ruf 112 an.", expected: []),
    ]

    static func links(_ view: ChatView) async {
        let report = SweepReport(file: "call_links.txt")
        var right = 0
        for (index, item) in linkCases.enumerated() {
            let found = PhoneLinks.matches(in: item.text).map { String(item.text[$0.range]) }
            let fits = found == item.expected
            right += fits ? 1 : 0
            report.add("FALL_\(index + 1)", "passt=\(fits) gefunden=\(found.joined(separator: "|")) "
                       + "soll=\(item.expected.joined(separator: "|")) text=\(item.text)")
        }
        let dialer = ProbeDialer()
        view.callDesk.stand(in: dialer, directory: FixtureContacts())
        let sample = "Du erreichst Maria unter 0170 1234567."
        let scanned = PhoneLinks.matches(in: sample).first?.number
        if let scanned { await view.placeCall(scanned) }
        let marked = URL(string: "tel:+49301234567").flatMap { Bubble.telNumber(of: $0) }
        if let marked { await view.placeCall(marked) }
        let wanted = [scanned?.digits, marked?.digits].compactMap { $0 }
        let fitted = dialer.numbers.map(\.digits) == wanted
        report.add("TASTENWEG", "erkannt=\(scanned?.masked ?? "-") modell=\(marked?.masked ?? "-") "
                   + "gewaehlt=\(dialer.numbers.map(\.masked)) passt=\(fitted) weg=\(view.callDesk.dialer.way)")
        view.callDesk.restore()
        report.add("SUMME", "erkannt=\(right)/\(linkCases.count) wahl_getippt=\(fitted)")
        flowLog.info("ANRUFNUMMERN fertig")
    }

    private static let contactSamples = [
        ContactRequest(person: "Mutter", group: "Familie", relation: .mother),
        ContactRequest(person: "Mama", relation: .mother),
        ContactRequest(person: "Papa", relation: .father),
    ]

    static func contacts(_: ChatView) async {
        let report = SweepReport(file: "call_contacts.txt")
        let directory = LiveContactDirectory()
        let access = await directory.access()
        report.add("ZUGRIFF", "\(access)")
        guard access == .granted else { return }
        do {
            let started = ContinuousClock.now
            let cards = try await directory.cards()
            let ties = cards.flatMap(\.ties)
            report.add("KARTEN", "anzahl=\(cards.count) mit_nummer=\(cards.filter { !$0.phones.isEmpty }.count) "
                       + "gruppen=\(Set(cards.flatMap(\.groups)).sorted().joined(separator: "|")) "
                       + "beziehungen=\(ties.count) ms=\(msOf(started.duration(to: .now)))")
            for tie in ties.prefix(20) {
                report.add("BEZIEHUNG", "art=\(tie.relation?.rawValue ?? "-") label=\(tie.label) name=\(tie.name)")
            }
            for (index, request) in contactSamples.enumerated() {
                report.add("AUFLOESUNG_\(index + 1)", "anfrage=\(request.stepWords) "
                           + describe(ContactMatching.resolve(request, in: cards)))
            }
        } catch {
            report.addFailure("KARTEN", error)
        }
        flowLog.info("ANRUFKONTAKTE fertig")
    }

    private static func describe(_ resolution: ContactResolution) -> String {
        guard case .unique(let target, let note) = resolution else {
            return ContactLookup.describe(resolution)
        }
        return "eindeutig name=\(target.name) art=\(target.label) nummer=\(target.number.masked) hinweis=\(note)"
    }

    static func dialer(_ view: ChatView) async {
        let report = SweepReport(file: "call_dialer.txt")
        let capability = DialerChoice.current()
        let flag = Bundle.main.object(forInfoDictionaryKey: DialerChoice.infoKey).map { "\($0)" } ?? "-"
        report.add("SYSTEM", "ios=\(UIDevice.current.systemVersion) "
                   + "catalyst=\(ProcessInfo.processInfo.isMacCatalystApp)")
        report.add("INFO_PLIST", "\(DialerChoice.infoKey)=\(flag.isEmpty ? "leer" : flag)")
        report.add("FAEHIGKEIT", capability.trace)
        report.add("LIVE_WEG", DialerChoice.dialer(for: capability).way)
        report.add("PROBE_SPERRE", "waehlt=\(view.callDesk.dialer.way) "
                   + "gesperrt=\(view.callDesk.dialer is ProbeDialer)")
        flowLog.info("ANRUFWEG fertig")
    }
}
#endif
