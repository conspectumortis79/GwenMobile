@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugClockProbe {
    private struct Case {
        let text: String
        let clock: Bool
        var zone: String?
    }

    private static let cases = [
        Case(text: "Wie spät ist es?", clock: true),
        Case(text: "Welches Datum haben wir heute?", clock: true),
        Case(text: "Welcher Wochentag ist heute?", clock: true),
        Case(text: "Wie spät ist es gerade in Tokio?", clock: true, zone: "Asia/Tokyo"),
        Case(text: "What time is it in New York right now?", clock: true, zone: "America/New_York"),
        Case(text: "Wann ist Ostern 2027?", clock: false),
        Case(text: "Wie viele Tage sind es noch bis Weihnachten?", clock: false),
        Case(text: "Erinnere mich morgen um 18 Uhr an den Müll", clock: false),
        Case(text: "Wie lange dauert ein Flug nach Tokio?", clock: false),
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.run(cases, file: "clock_route.txt", view: view, log: "UHRZEITROUTING fertig",
                             konfig: RouteSweep.konfig(view, cases.count,
                                                       extra: "zone_hier=\(TimeZone.current.identifier)"),
                             sentence: { $0.text },
                             fits: { item, plan in
                                 let request = clockRequest(plan)
                                 return item.clock ? request.map { $0.timeZone == item.zone } ?? false : request == nil
                             },
                             line: { item, plan, pass, ms in
                                 let request = clockRequest(plan)
                                 return "passt=\(pass) ist=\(plan.traceLine) zone=\(request?.timeZone ?? "-") "
                                     + "ort=\(request?.place ?? "-") ms=\(ms) text=\(item.text)"
                             },
                             summe: { "richtig=\($0)/\(cases.count)" })
    }

    private static func clockRequest(_ plan: SendPlan) -> ClockRequest? {
        guard case .clock(let request) = plan.primary.route else { return nil }
        return request
    }

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "clock_flow.txt")
        for (text, zone) in [("Wie spät ist es?", TimeZone.current),
                             ("Wie spät ist es in Tokio?", TimeZone(identifier: "Asia/Tokyo") ?? .current)] {
            let asked = Date()
            let answer = await view.ask(text, fresh: true)
            let reply = answer?.text ?? ""
            let accepted = [asked, Date()].map {
                ClockAnswer.render($0, zone: zone, date: .none, time: .short)
            }
            let fits = accepted.contains { reply.contains($0) }
            report.add("ABLAUF", "passt=\(fits) soll=\(Set(accepted).sorted().joined(separator: "|")) "
                       + "schritte=\(view.probeLastPlan?.traceLine ?? "-") antwort=\(TextLine.oneLine(reply, limit: 160))")
        }
        flowLog.info("UHRZEITABLAUF fertig")
    }
}
#endif
