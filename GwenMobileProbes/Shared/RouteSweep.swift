@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum RouteSweep {
    protocol KindedCase {
        var sentence: String { get }
        var kind: SendStepKind { get }
    }

    static func model(_ view: ChatView) -> String {
        view.settings.answeringModel(hasPictures: false)
    }

    static func konfig(_ view: ChatView, _ count: Int, extra: String = "") -> String {
        var text = "modell=\(model(view)) faelle=\(count) schluessel=\(view.settings.isConfigured)"
        if !extra.isEmpty { text += " " + extra }
        return text
    }

    static func trace<Case>(label: @escaping (Case) -> String, sentence: @escaping (Case) -> String,
                            detail: @escaping (SendPlan) -> String)
        -> (Case, SendPlan, Bool, Int) -> String {
        { item, plan, pass, ms in
            "passt=\(pass) soll=\(label(item)) ist=\(plan.traceLine) "
                + "detail=\(detail(plan)) ms=\(ms) satz=\(sentence(item))"
        }
    }

    static func summe(_ total: Int) -> (Int) -> String {
        { "richtig=\($0)/\(total)" }
    }

    static func describe(_ decision: ToolDecision?) -> String {
        guard let decision else { return "kein aufruf" }
        switch decision.route {
        case .chat: return decision.searchQuery == nil ? "chat" : "websuche"
        default: return decision.stepKind.rawValue
        }
    }

    static func ask(_ view: ChatView, text: String, history: [ChatMessage] = []) async -> RouterAsk {
        let settings = view.settings
        let model = model(view)
        let compact = settings.provider == .local
        var catalog = ""
        if !compact, settings.memory.enabled { catalog = await view.store.memory.catalog() }
        var watchCatalog = ""
        if !compact { watchCatalog = await view.store.watches.catalog() }
        return RouterAsk(baseURL: settings.baseURL, key: settings.apiKey, model: model, text: text,
                         context: SendContext(), history: RouterHistory.forRouting(history, compact: compact),
                         catalog: catalog, eraseHistoryWord: settings.spokenDeleteHistory,
                         thinking: settings.thinkingOffDirective(for: model),
                         watchCatalog: watchCatalog, compact: compact)
    }

    static func route(_ view: ChatView, _ sentence: String, history: [ChatMessage] = []) async -> SendPlan {
        await ToolRouter.plan(await ask(view, text: sentence, history: history))
    }

    static func routeAll<Case>(_ cases: [Case], file: String, view: ChatView, log: String,
                               history: (Case) -> [ChatMessage] = { _ in [] },
                               fits: @escaping (Case, SendPlan) -> Bool,
                               label: @escaping (Case) -> String,
                               sentence: @escaping (Case) -> String,
                               detail: @escaping (SendPlan) -> String,
                               requiresKey: Bool = false,
                               abortLog: String? = nil,
                               onResult: @escaping (Case, Bool) -> Void = { _, _ in }) async {
        await run(cases, file: file, view: view, log: log, konfig: konfig(view, cases.count),
                  sentence: sentence, history: history, fits: fits,
                  line: trace(label: label, sentence: sentence, detail: detail),
                  requiresKey: requiresKey, abortLog: abortLog, onResult: onResult,
                  summe: summe(cases.count))
    }

    static func routeAllKinded<Case: KindedCase>(_ cases: [Case], file: String, view: ChatView,
                                                 log: String,
                                                 history: (Case) -> [ChatMessage] = { _ in [] },
                                                 fits: @escaping (Case, SendPlan) -> Bool,
                                                 detail: @escaping (SendPlan) -> String,
                                                 requiresKey: Bool = false,
                                                 abortLog: String? = nil,
                                                 onResult: @escaping (Case, Bool) -> Void = { _, _ in }) async {
        await routeAll(cases, file: file, view: view, log: log, history: history, fits: fits,
                       label: { $0.kind.rawValue }, sentence: { $0.sentence }, detail: detail,
                       requiresKey: requiresKey, abortLog: abortLog, onResult: onResult)
    }

    static func run<Case>(_ cases: [Case], file: String, view: ChatView, log: String, konfig: String,
                          sentence: (Case) -> String,
                          history: (Case) -> [ChatMessage] = { _ in [] },
                          fits: (Case, SendPlan) -> Bool,
                          line: (Case, SendPlan, Bool, Int) -> String,
                          requiresKey: Bool = false,
                          abortLog: String? = nil,
                          onResult: (Case, Bool) -> Void = { _, _ in },
                          summe: (Int) -> String) async {
        let report = SweepReport(file: file)
        report.add("KONFIG", konfig)
        if requiresKey, !view.settings.isConfigured {
            report.add("ABBRUCH", "kein schluessel")
            flowLog.info("\(abortLog ?? log, privacy: .public)")
            return
        }
        var right = 0
        for (index, item) in cases.enumerated() {
            let started = ContinuousClock.now
            let plan = await route(view, sentence(item), history: history(item))
            let pass = fits(item, plan)
            right += pass ? 1 : 0
            onResult(item, pass)
            report.add("FALL_\(index + 1)",
                       line(item, plan, pass, msOf(started.duration(to: .now))))
        }
        report.add("SUMME", summe(right))
        flowLog.info("\(log, privacy: .public)")
    }
}
#endif
