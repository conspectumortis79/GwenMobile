@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
final class ProbeTimer: TimerSetting {
    private(set) var set: [(title: String?, duration: TimeInterval)] = []

    func set(_ request: TimerRequest) async -> TimerSettingResult {
        set.append((request.title, request.duration))
        flowMark("TIMER probe haelt den timer fest dauer=\(Int(request.duration))s titel=\(request.title ?? "-")")
        return .set(duration: request.duration, way: "probe")
    }
}

@MainActor
enum DebugTimerProbe {
    private struct RouteCase: RouteSweep.KindedCase {
        let sentence: String
        var kind: SendStepKind = .timer
        var minutes: Int?
        var seconds: Int?
    }

    private static let routeCases = [
        RouteCase(sentence: "Erstelle mir einen Timer für 10 Sekunden", seconds: 10),
        RouteCase(sentence: "Stelle einen Timer auf 5 Minuten", minutes: 5),
        RouteCase(sentence: "Bitte einen Timer auf 1 Minute 30 Sekunden", minutes: 1, seconds: 30),
        RouteCase(sentence: "Erinnere mich in 10 Minuten an den Tee", kind: .reminder),
        RouteCase(sentence: "Erinnere mich in 10 Sekunden an den Tee", kind: .reminder),
        RouteCase(sentence: "Wie spät ist es?", kind: .clock),
        RouteCase(sentence: "Erstelle mir einen Termin für morgen 9 Uhr mit dem Namen ProbeTimer", kind: .calendar),
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.routeAllKinded(routeCases, file: "timer_route.txt", view: view,
                                        log: "TIMERROUTING fertig", fits: fitting, detail: describe)
    }

    private static func fitting(_ item: RouteCase, plan: SendPlan) -> Bool {
        guard plan.primary.stepKind == item.kind else { return false }
        guard item.kind == .timer else { return true }
        guard case .timer(let request) = plan.primary.route else { return false }
        let wanted = Double((item.minutes ?? 0) * 60 + (item.seconds ?? 0))
        return request.duration == wanted
    }

    private static func describe(_ plan: SendPlan) -> String {
        switch plan.primary.route {
        case .timer(let request):
            return "timer:\(request.minutes ?? 0)m\(request.seconds ?? 0)s titel=\(request.title ?? "-")"
        case .reminder(let request):
            return "reminder:\(request.action.rawValue):\(request.title)|"
                + "m=\(request.minutes.map(String.init) ?? "-")s=\(request.seconds.map(String.init) ?? "-")"
        default:
            return plan.traceLine
        }
    }

    private static let flowSentences = [
        "Erstelle mir einen Timer für 10 Sekunden",
        "Stelle einen Timer auf 5 Minuten",
        "Erinnere mich in 10 Minuten an den Tee",
    ]

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "timer_flow.txt")
        let timer = ProbeTimer()
        let reminders = ProbeReminderStore()
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        view.timerDesk.stand(in: timer)
        view.reminderDesk.stand(in: reminders, places: ProbePlaceLookup())
        report.add("KONFIG", "faelle=\(flowSentences.count) schluessel=\(view.settings.isConfigured)")
        var right = 0
        for (index, sentence) in flowSentences.enumerated() {
            let started = ContinuousClock.now
            let answer = await view.ask(sentence, fresh: true)
            let fits = flowFits(index, timer: timer, reminders: reminders)
            right += fits ? 1 : 0
            report.add("FALL_\(index + 1)",
                       "passt=\(fits) timer=\(timer.set.map { Int($0.duration) }) "
                       + "erinnerungen=\(reminders.stored.count) ms=\(msOf(started.duration(to: .now))) "
                       + "antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 160)) satz=\(sentence)")
        }
        view.timerDesk.restore()
        view.reminderDesk.restore()
        let removed = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(removed) chats=\(view.store.conversations.count)")
        report.add("SUMME", "richtig=\(right)/\(flowSentences.count)")
        flowLog.info("TIMERABLAUF fertig")
    }

    private static func flowFits(_ index: Int, timer: ProbeTimer, reminders: ProbeReminderStore) -> Bool {
        switch index {
        case 0:
            return timer.set.count == 1 && Int(timer.set.last?.duration ?? 0) == 10 && reminders.stored.isEmpty
        case 1:
            return timer.set.count == 2 && Int(timer.set.last?.duration ?? 0) == 300 && reminders.stored.isEmpty
        default:
            return timer.set.count == 2
                && reminders.stored.contains { TextFolding.fold($0.title).contains("tee") }
        }
    }

    static func live() async {
        let report = SweepReport(file: "timer_live.txt")
        let setter = SystemTimerSetter()
        let result = await setter.set(TimerRequest(minutes: nil, seconds: 8, title: "GwenProbe"))
        report.add("STELLEN", result.trace)
        flowLog.info("TIMERLIVE fertig")
    }
}
#endif
