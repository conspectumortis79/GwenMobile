@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugChainParallelProbe {
    static let questions = ["Wie hoch ist die Zugspitze?",
                            "Wer ist Natalie Portman?",
                            "Wie viele Einwohner hat Berlin?"]
    static let orderMarks = ["zugspitze", "portman", "einwohner"]
    static let picturePrompts = ["a red circle on a white background",
                                "a blue square on a white background",
                                "a green triangle on a white background"]
    static let budget: Double = 240

    struct Answer {
        let text: String
        let ms: Int
    }

    struct Outcome {
        var answers: [Answer] = []
        var pictures = 0
        var arrivals: [Int] = []
        var ms = 0
        var finished = false
        var errorCount: Int {
            answers.filter { $0.text.contains(AnswerError.marker) }.count
        }
    }

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "chain_parallel.txt")
        let concurrent = ChainSchedule.stages(plan(questions, standalone: true).actions,
                                             limit: view.chainParallelSteps).map(\.count)
        let serial = ChainSchedule.stages(plan(questions, standalone: false).actions,
                                         limit: view.chainParallelSteps).map(\.count)
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "anbieter=\(view.settings.provider.rawValue) gleichzeitig=\(view.chainParallelSteps)")
        report.add("STUFEN", "unabhaengig=\(concurrent) abhaengig=\(serial)")
        guard view.settings.isConfigured else {
            report.add("SUMME", "abgebrochen kein schluessel")
            flowLog.info("KETTEPARALLEL abgebrochen kein schluessel")
            return
        }
        let routed = await routing(view, report: report)
        let drawn = await pictures(view, report: report)
        let order = await ordering(view, report: report)
        let speed = await speedup(view, report: report, stages: (concurrent, serial))
        let stop = await stopping(view, report: report)
        report.add("SUMME", "router=\(routed) reihenfolge=\(order) gleichzeitig=\(speed) "
                   + "bilder=\(drawn) abbruch=\(stop)")
        flowLog.info("KETTEPARALLEL fertig router=\(routed) reihenfolge=\(order) gleichzeitig=\(speed) bilder=\(drawn) abbruch=\(stop)")
    }

    private static func plan(_ wishes: [String], standalone: Bool) -> SendPlan {
        SendPlan(actions: wishes.map { words in
            var decision = ToolDecision(route: .chat)
            decision.wish = words
            decision.standalone = standalone
            return decision
        })
    }

    private static func routing(_ view: ChatView, report: SweepReport) async -> Bool {
        let sentence = "Wie hoch ist die Zugspitze? Und wie spät ist es in Tokio?"
        view.store.newConversation()
        guard let convID = view.store.current?.id else { return false }
        view.probeLastPlan = nil
        view.input = sentence
        await view.send()
        let steps = view.probeLastPlan?.actions ?? []
        let standalone = steps.map(\.standalone)
        let stages = ChainSchedule.stages(steps, limit: view.chainParallelSteps).map(\.count)
        let kinds = steps.map(\.stepKind.rawValue).joined(separator: "+")
        let ok = steps.count == 2 && Set(steps.map(\.stepKind)) == [.chat, .clock]
            && standalone.allSatisfy { $0 } && stages.count == 1 && stages[0] == 2
        report.add("ROUTER", "ok=\(ok) schritte=\(steps.count) werkzeuge=\(kinds) "
                   + "unabhaengig=\(standalone) stufen=\(stages)")
        for (index, step) in steps.enumerated() {
            report.add("ROUTER_\(index + 1)", "wunsch=" + TextLine.oneLine(step.wish ?? "-", limit: 90)
                       + " unabhaengig=\(step.standalone)")
        }
        for (index, answer) in assistants(view).enumerated() {
            report.add("ROUTER_BLASE_\(index + 1)", TextLine.oneLine(answer.text, limit: 140))
        }
        cleanup(view, convID)
        return ok
    }

    private static func pictures(_ view: ChatView, report: SweepReport) async -> Bool {
        guard view.settings.hasImageModel else {
            report.add("BILDER", "ok=false grund=kein bildmodell")
            return false
        }
        let one = await drawn(view, [picturePrompts[0]])
        let three = await drawn(view, picturePrompts)
        let serialThree = await drawn(view, picturePrompts, standalone: false)
        let mix = await drawnMixed(view)
        let straight = await drawnStraight(view)
        let imageStages = ChainSchedule.stages(plan(picturePrompts, standalone: true).actions).map(\.count)
        let alone = one.answers.count == 1 && three.answers.count == 1 && mix.answers.count == 1
        let counted = one.pictures == 1 && three.pictures == 3 && mix.pictures == 3
        let clean = one.errorCount == 0 && three.errorCount == 0 && mix.errorCount == 0
        let stepped = three.arrivals.count >= 2
        let early = mix.arrivals.first.map { $0 * 4 < mix.ms * 3 } ?? false
        let together = stepped && imageStages == [3] && three.pictures == 3 && three.errorCount == 0
        let straightClean = straight.finished && straight.answers.count == 1
            && straight.pictures == 2 && straight.errorCount == 0
        let faster = straightClean && mix.ms <= straight.ms + 2500
        let mixed = mixedStages() == [2, 1] && early && mix.pictures == 3 && mix.errorCount == 0
        report.add("BILDER", "ok=\(alone && counted && clean) eins_ms=\(one.ms) drei_ms=\(three.ms) "
                   + "seriell_drei_ms=\(serialThree.ms) anteil_prozent=\(share(three.ms, of: one.ms)) "
                   + "stufen_bild=\(imageStages) "
                   + "bilder=\(one.pictures)/\(three.pictures) blasen=\(one.answers.count)/\(three.answers.count) "
                   + "fehler=\(one.errorCount)/\(three.errorCount) zusammen=\(together) "
                   + "ankunft=\(three.arrivals) nacheinander_sichtbar=\(stepped)")
        report.add("BILDER_DREI", "fertig=\(three.finished) ms=\(three.ms) bilder=\(three.pictures) "
                   + "blasen=\(three.answers.count) "
                   + "texte=\(three.answers.map { TextLine.oneLine($0.text, limit: 40) }.joined(separator: " | "))")
        report.add("BILDER_MIX", "ok=\(mixed) "
                   + "stufen=\(mixedStages()) gemischt_ms=\(mix.ms) gerade_ms=\(straight.ms) "
                   + "anteil_eines_bildes=\(share(mix.ms, of: one.ms)) "
                   + "bilder=\(mix.pictures) blasen=\(mix.answers.count) fehler=\(mix.errorCount) "
                   + "ankunft=\(mix.arrivals) frueh_sichtbar=\(early) schneller=\(faster)")
        report.add("BILDER_MIX_TEXTE", "fertig=\(mix.finished) ms=\(mix.ms) bilder=\(mix.pictures) "
                   + "blasen=\(mix.answers.count) "
                   + "texte=\(mix.answers.map { TextLine.oneLine($0.text, limit: 140) }.joined(separator: " | "))")
        return alone && counted && clean && together && mixed && mix.pictures == 3 && stepped && early
    }

    static func mixedStages() -> [Int] {
        ChainSchedule.stages(mixedPlan().actions).map(\.count)
    }

    private static func mixedPlan() -> SendPlan {
        var chain = ToolDecision(route: .imageCreate, picturePrompt: "a purple hexagon on a white background")
        chain.wish = "Male ein lila Sechseck"
        chain.standalone = true
        var change = ToolDecision(route: .imageEdit,
                                  pictureInstruction: "make the purple hexagon black and white")
        change.wish = "Mach das Bild schwarz-weiß"
        change.standalone = false
        var star = ToolDecision(route: .imageCreate, picturePrompt: "an orange star on a white background")
        star.wish = "Male einen orangen Stern"
        star.standalone = true
        return SendPlan(actions: [chain, change, star])
    }

    private static func drawnMixed(_ view: ChatView) async -> Outcome {
        await run(view, mixedPlan(),
                  question: "Male ein lila Sechseck, mach es schwarz-weiß und male einen orangen Stern.",
                  watch: true)
    }

    private static func straightPlan() -> SendPlan {
        var create = ToolDecision(route: .imageCreate, picturePrompt: picturePrompts[0])
        create.wish = "Male einen roten Kreis"
        create.standalone = true
        var edit = ToolDecision(route: .imageEdit,
                                pictureInstruction: "make the red circle black and white")
        edit.wish = "Mach das Bild schwarz-weiß"
        edit.standalone = false
        return SendPlan(actions: [create, edit])
    }

    private static func drawnStraight(_ view: ChatView) async -> Outcome {
        await run(view, straightPlan(),
                  question: "Male einen roten Kreis und mach ihn schwarz-weiß.",
                  watch: true)
    }

    private static func share(_ part: Int, of whole: Int) -> Int {
        whole > 0 ? Int((Double(part) / Double(whole)) * 100) : 100
    }

    private static func drawn(_ view: ChatView, _ prompts: [String], standalone: Bool = true) async -> Outcome {
        let plan = SendPlan(actions: prompts.map { prompt in
            var decision = ToolDecision(route: .imageCreate, picturePrompt: prompt)
            decision.wish = "Male " + prompt
            decision.standalone = standalone
            return decision
        })
        return await run(view, plan, question: "Male " + prompts.joined(separator: ", "), watch: true)
    }

    private static func ordering(_ view: ChatView, report: SweepReport) async -> Bool {
        var chat = ToolDecision(route: .chat)
        chat.wish = "Wie hoch ist die Zugspitze?"
        chat.standalone = true
        var status = ToolDecision(route: .appStatus)
        status.wish = "Wie ist der Stand der App?"
        status.standalone = true
        let question = "Wie hoch ist die Zugspitze? Und wie ist der Stand der App?"
        let outcome = await run(view, SendPlan(actions: [chat, status]), question: question, watch: true)
        let mark = L.t("app_status_footer_local")
        let first = outcome.answers.first?.text ?? ""
        let second = outcome.answers.dropFirst().first?.text ?? ""
        let ok = outcome.finished && outcome.answers.count == 2
            && !first.contains(mark) && second.contains(mark)
        report.add("REIHENFOLGE", "ok=\(ok) blasen=\(outcome.answers.count) gesamt_ms=\(outcome.ms) "
                   + "erste_ms=\(outcome.answers.first?.ms ?? -1) "
                   + "zweite_ms=\(outcome.answers.dropFirst().first?.ms ?? -1) "
                   + "erste_status=\(first.contains(mark)) zweite_status=\(second.contains(mark))")
        for (index, answer) in outcome.answers.enumerated() {
            report.add("REIHENFOLGE_\(index + 1)", "ms=\(answer.ms) "
                       + TextLine.oneLine(answer.text, limit: 140))
        }
        return ok
    }

    private static func speedup(_ view: ChatView, report: SweepReport,
                                stages: ([Int], [Int])) async -> Bool {
        let question = questions.joined(separator: " ")
        var serial = await run(view, plan(questions, standalone: false), question: question)
        if serial.errorCount > 0 || !keepsOrder(serial.answers.first?.text ?? "") {
            flowMark("KETTEPROBE basis_wiederholt fehler=\(serial.errorCount)")
            serial = await run(view, plan(questions, standalone: false), question: question)
        }
        var parallel = await run(view, plan(questions, standalone: true), question: question)
        if parallel.errorCount > 0 || !keepsOrder(parallel.answers.first?.text ?? "") {
            flowMark("KETTEPROBE vergleich_wiederholt fehler=\(parallel.errorCount)")
            parallel = await run(view, plan(questions, standalone: true), question: question)
        }
        let serialText = serial.answers.first?.text ?? ""
        let parallelText = parallel.answers.first?.text ?? ""
        let saved = serial.ms - parallel.ms
        let share = serial.ms > 0 ? Int((Double(parallel.ms) / Double(serial.ms)) * 100) : 100
        let ok = serial.finished && parallel.finished
            && stages.0.count == 1 && stages.1.count == questions.count
            && serial.answers.count == 1 && parallel.answers.count == 1
            && serial.errorCount == 0 && parallel.errorCount == 0
            && keepsOrder(serialText) && keepsOrder(parallelText)
        report.add("GLEICHZEITIG", "ok=\(ok) nacheinander_ms=\(serial.ms) gleichzeitig_ms=\(parallel.ms) "
                   + "gespart_ms=\(saved) anteil_prozent=\(share) blasen=\(serial.answers.count)/\(parallel.answers.count) "
                   + "fehler=\(serial.errorCount)/\(parallel.errorCount) "
                   + "reihenfolge=\(keepsOrder(serialText))/\(keepsOrder(parallelText))")
        report.add("GLEICHZEITIG_NACHEINANDER", TextLine.oneLine(serialText, limit: 400))
        report.add("GLEICHZEITIG_GLEICHZEITIG", TextLine.oneLine(parallelText, limit: 400))
        return ok
    }

    private static func keepsOrder(_ text: String) -> Bool {
        let folded = TextFolding.fold(text)
        let places = orderMarks.compactMap { mark -> Int? in
            guard let found = folded.range(of: TextFolding.fold(mark)) else { return nil }
            return folded.distance(from: folded.startIndex, to: found.lowerBound)
        }
        guard places.count == orderMarks.count else { return false }
        return zip(places, places.dropFirst()).allSatisfy { $0 < $1 }
    }

    private static func stopping(_ view: ChatView, report: SweepReport) async -> Bool {
        let question = questions.joined(separator: " ")
        guard let prepared = prepare(view, plan(questions, standalone: true), question: question) else {
            report.add("ABBRUCH", "ok=false grund=kein lauf")
            return false
        }
        let done = LockedValue(false)
        let run = Task { @MainActor in
            await view.run(prepared.turn)
            done.set(true)
        }
        try? await Task.sleep(for: .milliseconds(1500))
        let beforeStop = assistants(view).count
        run.cancel()
        let ended = await ProbeWait.until(60) { done.current }
        let answers = assistants(view)
        let failed = answers.filter { $0.text.contains(AnswerError.marker) }.count
        let ok = ended && failed == 0
        report.add("ABBRUCH", "ok=\(ok) beendet=\(ended) blasen_vor_stopp=\(beforeStop) "
                   + "blasen_danach=\(answers.count) fehler=\(failed)")
        for (index, answer) in answers.enumerated() {
            report.add("ABBRUCH_\(index + 1)", TextLine.oneLine(answer.text, limit: 140))
        }
        cleanup(view, prepared.convID)
        return ok
    }

    private static func run(_ view: ChatView, _ plan: SendPlan, question: String,
                            watch: Bool = false) async -> Outcome {
        guard let prepared = prepare(view, plan, question: question) else { return Outcome() }
        let began = ContinuousClock.now
        let done = LockedValue(false)
        let task = Task { @MainActor in
            await view.run(prepared.turn)
            done.set(true)
        }
        var outcome = Outcome()
        var known = Set<UUID>()
        func collect() {
            let before = outcome.pictures
            let current = assistants(view)
            for message in current where !known.contains(message.id) {
                known.insert(message.id)
                outcome.answers.append(Answer(text: message.text, ms: elapsed(since: began)))
            }
            outcome.pictures = current.reduce(0) { $0 + ($1.outImages?.count ?? 0) }
            if outcome.pictures > before { outcome.arrivals.append(elapsed(since: began)) }
        }
        if watch {
            while !done.current {
                collect()
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        outcome.finished = await ProbeWait.until(budget) { done.current }
        collect()
        outcome.ms = elapsed(since: began)
        task.cancel()
        cleanup(view, prepared.convID)
        return outcome
    }

    private static func prepare(_ view: ChatView, _ plan: SendPlan,
                               question: String) -> (convID: UUID, turn: RoutedSend)? {
        view.store.newConversation()
        guard let convID = view.store.current?.id else { return nil }
        let message = ChatMessage(role: .user, text: question)
        guard view.store.appendMessage(message, to: convID) else { return nil }
        let turn = RoutedSend(text: question, plan: plan,
                              turn: ModelTurn(messages: [message], images: []),
                              history: [message], attachments: [], files: [],
                              convID: convID, started: Date())
        return (convID, turn)
    }

    private static func assistants(_ view: ChatView) -> [ChatMessage] {
        (view.store.current?.messages ?? []).filter { $0.role == .assistant }
    }

    private static func cleanup(_ view: ChatView, _ convID: UUID) {
        _ = view.store.removeConversation(convID)
    }

    private static func elapsed(since began: ContinuousClock.Instant) -> Int {
        msOf(began.duration(to: .now))
    }
}
#endif
