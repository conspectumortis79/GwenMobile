@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugWishRoutingProbe {
    private struct Variant {
        let name: String
        let index: Int
        let attachable: Bool
        var thinks = false
    }

    static let wishes = ["Wer ist Natalie Portman?", "Zeig mir Bilder von Natalie Portman.",
                         "Erstelle mir eine Comic-Figur von Natalie Portman.", "Schau wo der nächste Rewe Markt ist."]
    static let rounds = ProbeRounds.maximum

    private static let variants = [
        Variant(name: "mit_vorgeschichte_mit_bildwerkzeug", index: 3, attachable: true),
        Variant(name: "mit_vorgeschichte_mit_bildwerkzeug_denkend", index: 3, attachable: true, thinks: true),
    ]

    static func sweep(_ view: ChatView) async {
        let report = SweepReport(file: "wish_routing.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let base = ToolRouter.systemBlock(now: SystemPrompt.currentDate(), context: SendContext(), transcript: "")
        report.add("KONFIG", "modell=\(model) runden=\(rounds) wunsch=\(wishes[3])")
        for variant in variants {
            var hits = 0
            for round in 1...rounds {
                let listed = Array(wishes.prefix(variant.index)) + [wishes[3]]
                let system = WishRouting.system(base, wish: variant.index, of: listed,
                                                offersEdit: variant.attachable)
                let started = Date()
                let decision = await ToolRouter.plan(asking: {
                    try await HTTP.jsonData(try ToolRouter.request(baseURL: settings.baseURL, key: settings.apiKey,
                                                                   model: model, text: wishes[3], system: system,
                                                                   attachable: variant.attachable,
                                                                   thinking: variant.thinks
                                                                    ? settings.thinkingDirective(for: model)
                                                                    : settings.thinkingOffDirective(for: model)))
                }).first
                let detail = decision.map { $0.stepKind.rawValue + " " + $0.stepDetail } ?? "keine"
                var first = "-"
                if case .nearbyPlace(let terms, _)? = decision?.route { first = terms.first ?? "-" }
                let hit = TextFolding.fold(first).contains("rewe")
                hits += hit ? 1 : 0
                report.add("\(variant.name)_\(round)", "erster_begriff_rewe=\(hit) erster=\(first) "
                           + "ms=\(Int(Date().timeIntervalSince(started) * 1000)) "
                           + TextLine.oneLine(detail, limit: 120))
                try? await Task.sleep(for: .milliseconds(600))
            }
            report.add("\(variant.name)_SUMME", "rewe_zuerst=\(hits)/\(rounds)")
        }
        flowLog.info("WUNSCHROUTING fertig")
    }

    static let plannerWish = "Trag einen Termin morgen um 12 Uhr ein"
    static let plannerRounds = ProbeRounds.maximum

    static func plannerDates(_ view: ChatView) async {
        let report = SweepReport(file: "wish_planer.txt")
        let settings = view.settings
        let model = settings.chatModel
        let now = Date()
        let day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let made = (8...11).compactMap { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        let sameMessage = made.map { "- Termin \u{2014} \(Formatters.eventDateTime($0)) \u{2014} notifications: none "
                                     + "\u{2014} calendar: Arbeit" }.joined(separator: "\n")
        let wanted = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        report.add("KONFIG", "modell=\(model) wunsch=\(plannerWish) soll=\(Formatters.eventDateTime(wanted))")
        let real = CalendarService.upcomingContext()
        let whole = "Trag Termine morgen um 8, 9, 10, 11, 12 und 13 Uhr ein, zeig mir Bilder vom Kölner Dom und vom "
            + "Eiffelturm, sag mir, wie hoch die Zugspitze ist, und wo ist die nächste Apotheke?"
        let notes = made.map { "\u{2714} Termin angelegt: Termin \u{2014} \(Formatters.eventDateTime($0))" }
            .joined(separator: "\n\n")
        let chain = [ChatMessage(role: .user, text: whole), ChatMessage(role: .assistant, text: notes)]
        let variants: [(String, [ChatMessage])] = [("mit_ganzer_nachricht_im_verlauf", chain),
                                                   ("ohne_verlauf", [])]
        for (name, history) in variants {
            var right = 0
            for round in 1...plannerRounds {
                let plan = try? await QwenAPI.calendarPlan(baseURL: settings.baseURL, key: settings.apiKey,
                                                           model: model, instruction: plannerWish,
                                                           history: history,
                                                           events: [real, sameMessage].filter { !$0.isEmpty }
                                                            .joined(separator: "\n"),
                                                           calendars: CalendarService.calendarsContext(),
                                                           thinking: settings.thinkingOffDirective(for: model))
                let hit = plan?.startDate == wanted
                right += hit ? 1 : 0
                report.add("\(name)_\(round)", "richtig=\(hit) start=\(plan?.start ?? "-") "
                           + "aktion=\(plan.map { "\($0.action)" } ?? "-")")
            }
            report.add("\(name)_SUMME", "richtig=\(right)/\(plannerRounds)")
        }
        flowLog.info("WUNSCHPLANER fertig")
    }

    static let pictureChainSentence = "please create a picture with two men playing volleyball on the beach, "
        + "and next to them a dolphin in the water watching."

    static func pictureChain(_ view: ChatView) async {
        let report = SweepReport(file: "picture_chain.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let ask = RouterAsk(baseURL: settings.baseURL, key: settings.apiKey, model: model,
                            text: pictureChainSentence, context: SendContext(), history: [],
                            thinking: settings.thinkingOffDirective(for: model))
        let plan = await ToolRouter.plan(ask)
        let steps = plan.actions.map { step in
            step.stepKind.rawValue + " " + TextLine.oneLine(step.stepDetail, limit: 140)
        }
        let pictures = plan.actions.filter { $0.stepKind == .create || $0.stepKind == .edit }
        report.add("KONFIG", "modell=\(model)")
        report.add("SATZ", pictureChainSentence)
        report.add("PLAN", steps.joined(separator: " | "))
        report.add("SUMME", "schritte=\(plan.actions.count) bild=\(pictures.count)")
        let first = ToolDecision(route: .imageCreate,
                                 picturePrompt: "Two men playing volleyball on the beach",
                                 wish: "please create a picture with two men playing volleyball on the beach")
        let second = ToolDecision(route: .imageEdit,
                                  pictureInstruction: "Add a dolphin in the water next to them, watching",
                                  wish: "and next to them a dolphin in the water watching")
        let system = ToolRouter.systemBlock(now: SystemPrompt.currentMoment(), context: SendContext(), transcript: "")
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let thinking = settings.thinkingOffDirective(for: model)
        let checked = await PictureChainCheck.reconciled([first, second], message: pictureChainSentence) { text, hint in
            await ToolRouter.plan(asking: {
                try await HTTP.jsonData(try ToolRouter.request(baseURL: baseURL, key: key,
                                                               model: model, text: text,
                                                               system: system + "\n\n" + hint,
                                                               attachable: false, thinking: thinking))
            })
        }
        let chain = checked.map { step in
            step.stepKind.rawValue + " " + TextLine.oneLine(step.stepDetail, limit: 140)
        }
        report.add("KETTE", chain.joined(separator: " | "))
        report.add("KETTE_SUMME", "schritte=\(checked.count)")
        flowLog.info("BILDKETTE probe fertig schritte=\(plan.actions.count) bild=\(pictures.count) kette=\(checked.count)")
    }

    static let editChangeSentence = "Das erste Bild, das du von Lucio Corsi gemacht hast, soll verändert werden "
        + "in der Hinsicht, dass er eine doppelt so große Nase hat, die Haare zu sauber sind. Das Bild an gelben "
        + "Stich hat und hinten irgendwelche Leute in Sprechblasen schreiben."

    static let editVariantsSentence = "Mach mir vier Varianten von dem Bild: eine mit doppelter Nase, eine mit "
        + "sauberen Haaren, eine mit gelbem Stich und eine mit Leuten in Sprechblasen."

    static func editChain(_ view: ChatView) async {
        let report = SweepReport(file: "picture_edit_chain.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let thinking = settings.thinkingOffDirective(for: model)
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let system = ToolRouter.systemBlock(now: SystemPrompt.currentMoment(), context: SendContext(),
                                            transcript: "")
        report.add("KONFIG", "modell=\(model)")
        for (name, sentence) in [("AENDERUNGEN", editChangeSentence), ("VARIANTEN", editVariantsSentence)] {
            let wishes = await WishSplitter.splitParts(asking: {
                try await QwenAPI.askText(try WishSplitter.request(baseURL: baseURL, key: key, model: model,
                                                                  text: sentence, thinking: thinking))
            })?.map(\.text)
            report.add("ZERLEGUNG_\(name)", "anzahl=\(wishes?.count ?? -1) "
                       + (wishes?.map { TextLine.oneLine($0, limit: 90) }.joined(separator: " | ") ?? "-"))
            let edits = (1...4).map { index in
                ToolDecision(route: .imageEdit, pictureInstruction: "Änderung \(index)",
                             wish: "Änderung \(index)")
            }
            let checked = await PictureChainCheck.reconciled(edits, message: sentence) { text, hint in
                await ToolRouter.plan(asking: {
                    try await HTTP.jsonData(try ToolRouter.request(baseURL: baseURL, key: key, model: model,
                                                                   text: text, system: system + "\n\n" + hint,
                                                                   attachable: false, thinking: thinking))
                })
            }
            report.add("KETTE_\(name)", "vorher=\(edits.count) nachher=\(checked.count) "
                       + checked.map { $0.stepKind.rawValue }.joined(separator: ","))
        }
        flowLog.info("BILDKETTE aenderungen fertig")
    }

    static let llmComparisonSentence = "bitte vergleiche mir die LLMs gwen 3.8 flash next und deepseek v4.1 flash was die perfomance angeht"
    static let performanceSentence = "Wie performant sind gwen 3.8 flash next und deepseek v4.1 flash?"
    static let priceSentence = "Vergleiche die Preise von einer PlayStation 5 und einer Xbox Series X."
    static let actualSentence = "Ich würde gerne einen Vergleich zwischen zwei NLMs KILLMs haben wollen. Und zwar Gwen QWEN 38 Flash Next im Vergleich zu Deep Seek V4. Punkt eins Flash 1017. Bitte vergleiche die ganzen KI Performance Statistiken Und was besser ist."
    static let cleanSentence = "Vergleiche die LLMs Qwen 3.8 Flash Next und DeepSeek V4.1 Flash hinsichtlich ihrer Performance."

    private static func planText(_ steps: [ToolDecision]) -> String {
        steps.map { $0.stepKind.rawValue + " " + TextLine.oneLine($0.stepDetail, limit: 160) }
            .joined(separator: " | ")
    }

    static func llmComparison(_ view: ChatView) async {
        let report = SweepReport(file: "llm_comparison.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let thinking = settings.thinkingOffDirective(for: model)
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let system = ToolRouter.systemBlock(now: SystemPrompt.currentMoment(), context: SendContext(),
                                            transcript: "")
        report.add("KONFIG", "modell=\(model) basis=\(baseURL)")
        let cases = [("LLM_VERGLEICH", llmComparisonSentence), ("PERFORMANCE", performanceSentence),
                     ("PREIS_VERGLEICH", priceSentence), ("ECHT", actualSentence), ("SAUBER", cleanSentence)]
        for (name, sentence) in cases {
            report.add("SATZ_\(name)", sentence)
            let whole = await ToolRouter.plan(asking: {
                try await HTTP.jsonData(try ToolRouter.request(baseURL: baseURL, key: key, model: model,
                                                               text: sentence, system: system,
                                                               attachable: false, thinking: thinking))
            })
            report.add("GANZ_\(name)", planText(whole))
            let wishes = await WishSplitter.splitParts(asking: {
                try await QwenAPI.askText(try WishSplitter.request(baseURL: baseURL, key: key, model: model,
                                                                  text: sentence, thinking: thinking))
            })?.map(\.text)
            report.add("WUENSCHE_\(name)", wishes.map { "anzahl=\($0.count) " + $0.joined(separator: " | ") }
                       ?? "unlesbar")
            if let wishes {
                for (index, wish) in wishes.enumerated() {
                    let focused = WishRouting.system(system, wish: index, of: wishes, offersEdit: false)
                    let plan = await ToolRouter.plan(asking: {
                        try await HTTP.jsonData(try ToolRouter.request(baseURL: baseURL, key: key, model: model,
                                                                       text: wish, system: focused,
                                                                       attachable: false, thinking: thinking))
                    })
                    report.add("WUNSCH_\(name)_\(index + 1)", planText(plan))
                }
            }
            let ask = RouterAsk(baseURL: baseURL, key: key, model: model, text: sentence,
                                context: SendContext(), history: [], thinking: thinking)
            let steps = await ToolRouter.steps(ask)
            report.add("FINAL_\(name)", planText(steps))
        }
        flowLog.info("LLMVERGLEICH fertig")
    }

    static func editSteps(_ view: ChatView) async {
        let report = SweepReport(file: "picture_edit_steps.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let thinking = settings.thinkingOffDirective(for: model)
        report.add("KONFIG", "modell=\(model)")
        for (name, sentence) in [("AENDERUNGEN", editChangeSentence), ("VARIANTEN", editVariantsSentence)] {
            let ask = RouterAsk(baseURL: settings.baseURL, key: settings.apiKey, model: model, text: sentence,
                                context: SendContext(rememberedImage: true), history: [], thinking: thinking)
            let steps = await ToolRouter.stepsImpl(ask)
            report.add("SCHRITTE_\(name)", "anzahl=\(steps.count) "
                       + steps.map { $0.stepKind.rawValue }.joined(separator: ","))
            report.add("DETAIL_\(name)", steps.map { step in
                step.stepKind.rawValue + " " + TextLine.oneLine(step.stepDetail, limit: 400)
            }.joined(separator: " | "))
        }
        flowLog.info("BILDSCHRITTE probe fertig")
    }
}
#endif
