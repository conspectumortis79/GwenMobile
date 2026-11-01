@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import MessageUI

@MainActor
final class ProbeMessenger: MessageSending {
    private(set) var sent: [(text: String, number: DialNumber)] = []

    var way: String { "probe_ohne_versand" }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        sent.append((text, number))
        flowMark("NACHRICHT probe haelt den versand zurueck nummer=\(number.masked) zeichen=\(text.count)")
        return .sent(direct: true)
    }
}

@MainActor
enum DebugMessageProbe {
    private struct RouteCase {
        let text: String
        let wanted: SendStepKind
        var relation: ContactRelation?
        var words: [String] = []
        var exact = true
    }

    private static let routeCases = [
        RouteCase(text: "Schreib Mama, dass ich später komme", wanted: .message, relation: .mother, words: ["später"]),
        RouteCase(text: "Schick Peter Müller eine SMS: Bin gleich da", wanted: .message, words: ["gleich da"]),
        RouteCase(text: "Sende Familie: Mutter eine Nachricht, dass das Essen fertig ist", wanted: .message,
                  relation: .mother, words: ["Essen"]),
        RouteCase(text: "Text my sister that I love her", wanted: .message, relation: .sister, words: ["love"]),
        RouteCase(text: "Wie schreibe ich eine SMS auf dem iPhone?", wanted: .chat, exact: false),
        RouteCase(text: "Schreib mir einen Text über Katzen", wanted: .chat, exact: false),
        RouteCase(text: "Ruf Mama an", wanted: .call),
        RouteCase(text: "Spiel Musik", wanted: .music),
        RouteCase(text: "Wie spät ist es?", wanted: .clock),
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.run(routeCases, file: "sms_route.txt", view: view, log: "SMSROUTING fertig",
                             konfig: RouteSweep.konfig(view, routeCases.count,
                                                       extra: "sendet=\(view.messageDesk.sender.way)"),
                             sentence: { $0.text },
                             fits: { fitting($0, kind: $1.primary.stepKind, request: messageRequest($1)) },
                             line: { item, plan, pass, ms in
                                 "passt=\(pass) soll=\(item.wanted.rawValue) ist=\(plan.traceLine) "
                                     + "an=\(messageRequest(plan)?.recipient.stepWords ?? "-") "
                                     + "text=\(messageRequest(plan)?.text ?? "-") ms=\(ms) satz=\(item.text)"
                             },
                             summe: { "richtig=\($0)/\(routeCases.count)" })
    }

    private static func messageRequest(_ plan: SendPlan) -> MessageRequest? {
        guard case .message(let request) = plan.primary.route else { return nil }
        return request
    }

    private static func fitting(_ item: RouteCase, kind: SendStepKind, request: MessageRequest?) -> Bool {
        guard item.wanted == .message else { return item.exact ? kind == item.wanted : kind != .message }
        guard let request else { return false }
        if let relation = item.relation, request.recipient.relation != relation { return false }
        let text = TextFolding.fold(request.text)
        return item.words.allSatisfy { text.contains(TextFolding.fold($0)) }
    }

    private static let flowCases = [
        FlowCase(text: "Schreib Familie: Mutter, dass ich später komme", number: FixtureContacts.motherMobile,
                 words: ["Maria Probemuster", "später"]),
        FlowCase(text: "Schick Peter eine SMS: Bin gleich da", number: nil, words: ["Alphaprobe", "Betaprobe"]),
        FlowCase(text: "Schreib Otto Ohnenummer, dass es regnet", number: nil, words: ["Otto Ohnenummer"]),
        FlowCase(text: "Wie schreibe ich eine SMS?", number: nil, words: []),
    ]

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "sms_flow.txt")
        let messenger = ProbeMessenger()
        view.messageDesk.stand(in: messenger, directory: FixtureContacts())
        report.add("KONFIG", "sendet=\(view.messageDesk.sender.way) kontakte=\(FixtureContacts.cards.count)")
        var right = 0
        for (index, item) in flowCases.enumerated() {
            let before = messenger.sent.count
            let answer = await view.ask(item.text, fresh: true)
            let sent = Array(messenger.sent.dropFirst(before))
            let expected = item.number.flatMap(DialNumber.init)
            let numberFits = expected.map { sent.map(\.number) == [$0] } ?? sent.isEmpty
            let reply = TextFolding.fold(answer?.text ?? "")
            let wordsFit = item.words.allSatisfy { reply.contains(TextFolding.fold($0)) }
            right += numberFits && wordsFit ? 1 : 0
            report.add("FALL_\(index + 1)", "passt=\(numberFits && wordsFit) an=\(sent.map(\.number.masked)) "
                       + "soll=\(expected?.masked ?? "nichts") text=\(sent.map(\.text)) "
                       + "antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 160))")
        }
        report.add("SUMME", "richtig=\(right)/\(flowCases.count) versendet_gesamt=\(messenger.sent.count)")
        flowLog.info("SMSABLAUF fertig")
    }

    private static let languageSentences: [(sentence: String, german: Bool)] = [
        ("Text my sister that I love her", false),
        ("Send Tom a message saying the meeting starts at five", false),
        ("Schreib Mama, dass ich später komme", true),
        ("Schick Peter eine Nachricht, dass das Treffen um fünf beginnt", true),
    ]

    static func language(_ view: ChatView) async {
        let report = SweepReport(file: "sms_language.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        report.add("KONFIG", "modell=\(model) runden=\(ProbeRounds.maximum)")
        var kept = 0
        var total = 0
        for (sentence, german) in languageSentences {
            for round in 1...ProbeRounds.maximum {
                let plan = await ToolRouter.plan(RouterAsk(baseURL: settings.baseURL, key: settings.apiKey,
                                                           model: model,
                                                           text: sentence, context: SendContext(), history: [],
                                                           thinking: settings.thinkingOffDirective(for: model)))
                let request: MessageRequest? = {
                    if case .message(let request) = plan.primary.route { return request }
                    return nil
                }()
                let same = request.map { !$0.text.isEmpty && looksGerman($0.text) == german }
                total += 1
                kept += same == true ? 1 : 0
                report.add("RUNDE_\(round)", "sprache_behalten=\(same.map(String.init) ?? "keine_nachricht") "
                           + "an=\(request?.recipient.person ?? "-") text=\(request?.text ?? "-") satz=\(sentence)")
            }
        }
        report.add("SUMME", "sprache_behalten=\(kept)/\(total)")
        flowLog.info("SMSSPRACHE fertig")
    }

    private static func looksGerman(_ text: String) -> Bool {
        let words = Set(ContactWords.words(text))
        return !words.isDisjoint(with: ["ich", "dich", "du", "das", "die", "der", "um", "funf", "beginnt", "komme",
                                        "spater", "treffen", "liebe", "bin", "ist"])
    }

    static func check(_ view: ChatView) async {
        let report = SweepReport(file: "sms_check.txt")
        let capability = MessagingChoice.current()
        let flag = Bundle.main.object(forInfoDictionaryKey: MessagingChoice.infoKey).map { "\($0)" } ?? "-"
        report.add("INFO_PLIST", "\(MessagingChoice.infoKey)=\(flag.isEmpty ? "leer" : flag)")
        report.add("FAEHIGKEIT", capability.trace)
        report.add("FORMULAR", "kann_senden=\(MFMessageComposeViewController.canSendText())")
        report.add("LIVE_WEG", MessagingChoice.sender(for: capability).way)
        report.add("PROBE_SPERRE", "sendet=\(view.messageDesk.sender.way) "
                   + "gesperrt=\(view.messageDesk.sender is ProbeMessenger)")
        flowLog.info("SMSPRUEFUNG fertig")
    }
}
#endif
