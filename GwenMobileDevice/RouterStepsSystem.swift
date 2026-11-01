@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation

extension ToolRouter {
    static func stepsImpl(_ ask: RouterAsk) async -> [ToolDecision] {
        let routerStarted = ContinuousClock.now
        let baseURL = ask.baseURL
        let key = ask.key
        let model = ask.model
        let text = ask.text
        let context = ask.context
        let history = ask.history
        let pictures = ask.allPictures
        let catalog = ask.catalog
        let eraseHistoryWord = ask.eraseHistoryWord
        let document = ask.document
        let thinking = ask.thinking
        let watchCatalog = ask.watchCatalog
        let compact = ask.compact
        let now = SystemPrompt.currentMoment()
        let system = systemBlock(now: now, context: context,
                                 transcript: ConversationTranscript.withoutTheNewestQuestion(from: history),
                                 catalog: catalog, eraseHistoryWord: eraseHistoryWord,
                                 document: document, watchCatalog: watchCatalog)
        let attachable = !compact && (context.attachedImage || context.rememberedImage)
        let translatesOnDevice = !context.textNeedsTheModel
        let knownLists = ask.reminderLists
        async let whole = plan(asking: {
            let started = ContinuousClock.now
            defer { flowMark("ROUTER teil=ganz dauer_ms=\(msOf(started.duration(to: .now)))") }
            return try await HTTP.jsonData(try request(baseURL: baseURL, key: key, model: model, text: text,
                                                       system: system, attachable: attachable,
                                                       translatesOnDevice: translatesOnDevice,
                                                       pictures: pictures, parallel: true, compact: compact,
                                                       thinking: thinking))
        })
        async let split = WishSplitter.splitParts(asking: {
            let started = ContinuousClock.now
            defer { flowMark("ROUTER teil=zerlegung dauer_ms=\(msOf(started.duration(to: .now)))") }
            return try await QwenAPI.askText(try WishSplitter.request(baseURL: baseURL, key: key, model: model,
                                                                      text: text, thinking: thinking))
        }, knownLists: knownLists)
        let parts = await split
        let wishes = parts?.map(\.text)
        let listed = wishes ?? []
        let independent = Set((parts ?? []).enumerated().compactMap { $0.element.independent ? $0.offset : nil })
        async let routing = WishRouting.routed(listed, independent: independent) { index, wish, offersEdit in
            let focused = WishRouting.system(system, wish: index, of: listed, offersEdit: offersEdit)
            return try await HTTP.jsonData(try request(baseURL: baseURL, key: key, model: model, text: wish,
                                                       system: focused, attachable: attachable || offersEdit,
                                                       translatesOnDevice: translatesOnDevice,
                                                       pictures: pictures, compact: compact, thinking: thinking))
        }
        let calls = await whole
        let routed = await routing
        let chosen = WishRouting.chosen(wishes: wishes, whole: calls, routed: routed)
        let scoped = await WishRouting.scoped(chosen, parts: parts, lists: knownLists,
                                              placeExists: ask.reminderPlaceExists)
        let videoApplied = WishRouting.applyingVideoWishes(scoped, parts: parts)
        if videoApplied.map(\.stepKind) != scoped.map(\.stepKind) {
            flowMark("VIDEO-WUNSCH erkannt "
                     + "vorher=\(scoped.map { $0.stepKind.rawValue }.joined(separator: "+")) "
                     + "nachher=\(videoApplied.map { $0.stepKind.rawValue }.joined(separator: "+"))")
        }
        let videoVerified = await verifyingVideoWish(videoApplied, parts: parts, ask: ask)
        if videoVerified.map(\.stepKind) != videoApplied.map(\.stepKind) {
            flowMark("VIDEO-PRUEFUNG uebernimmt "
                     + "vorher=\(videoApplied.map { $0.stepKind.rawValue }.joined(separator: "+")) "
                     + "nachher=\(videoVerified.map { $0.stepKind.rawValue }.joined(separator: "+"))")
        }
        flowMark("WÜNSCHE anzahl=\(wishes.map { String($0.count) } ?? "unlesbar") "
                 + "unabhaengig=\(independent.count) "
                 + "ganz=\(calls.map { $0.stepKind.rawValue }.joined(separator: ",")) "
                 + "je_wunsch=\(routed.map { $0.stepKind.rawValue }.joined(separator: ",")) "
                 + "gewählt=\(videoVerified.map { $0.stepKind.rawValue }.joined(separator: ","))")
        for (index, wish) in (wishes ?? []).enumerated() {
            flowMarkPersonal("WUNSCH \(index + 1)=\(TextLine.oneLine(wish, limit: 120))")
        }
        let pictureChecked = await PictureChainCheck.reconciled(videoVerified, message: text) { pictureText, hint in
            await plan(asking: {
                try await HTTP.jsonData(try request(baseURL: baseURL, key: key, model: model, text: pictureText,
                                                    system: system + "\n\n" + hint,
                                                    attachable: attachable,
                                                    translatesOnDevice: translatesOnDevice,
                                                    pictures: pictures, compact: compact, thinking: thinking))
            })
        }
        if pictureChecked.map(\.stepKind) != videoVerified.map(\.stepKind) {
            flowMark("BILDKETTE geprueft "
                     + "vorher=\(videoVerified.map { $0.stepKind.rawValue }.joined(separator: "+")) "
                     + "nachher=\(pictureChecked.map { $0.stepKind.rawValue }.joined(separator: "+"))")
        }
        let reconciled = await AppointmentReminderCheck.reconciled(pictureChecked, message: text) { wish, hint in
            await plan(asking: {
                try await HTTP.jsonData(try request(baseURL: baseURL, key: key, model: model, text: wish,
                                                    system: system + "\n\n" + hint,
                                                    attachable: attachable,
                                                    translatesOnDevice: translatesOnDevice,
                                                    pictures: pictures, compact: compact, thinking: thinking))
            })
        }
        if reconciled.map(\.stepKind) != pictureChecked.map(\.stepKind) {
            flowMark("TERMIN/ERINNERUNG geprueft "
                     + "vorher=\(pictureChecked.map { $0.stepKind.rawValue }.joined(separator: "+")) "
                     + "nachher=\(reconciled.map { $0.stepKind.rawValue }.joined(separator: "+"))")
        }
        var checked: [ToolDecision] = []
        for decision in reconciled {
            let wish = decision.wish ?? text
            let wishIndex = listed.firstIndex(of: wish) ?? 0
            let focused = listed.count > 1
                ? WishRouting.system(system, wish: wishIndex, of: listed, offersEdit: false) : system
            var current = decision
            for check in confirmations {
                let corrected = await check.checked(current, wish: wish) { hint in
                    let rewritten = focused + "\n\n" + hint
                    return await plan(asking: {
                        try await HTTP.jsonData(try request(baseURL: baseURL, key: key, model: model, text: wish,
                                                            system: rewritten, attachable: attachable,
                                                            translatesOnDevice: translatesOnDevice,
                                                            pictures: pictures, compact: compact, thinking: thinking))
                    }).first
                }
                current = corrected
                current.standalone = decision.standalone
            }
            checked.append(current)
        }
        flowMark("ROUTER dauer_ms=\(msOf(routerStarted.duration(to: .now)))")
        return checked.map { $0.withChatText(excluding: text, history: history) }
    }

    private static func verifyingVideoWish(_ decisions: [ToolDecision], parts: [WishPart]?,
                                           ask: RouterAsk) async -> [ToolDecision] {
        guard ask.videoGenerationAvailable, decisions.count == 1,
              let decision = decisions.first,
              decision.stepKind == .chat || decision.stepKind == .create else { return decisions }
        if parts?.first?.isVideo == true { return decisions }
        let wish = parts?.first?.text ?? ask.text
        guard !wish.trimmed.isEmpty,
              let request = try? VideoWishCheck.request(baseURL: ask.baseURL, key: ask.key,
                                                        model: ask.model, wish: wish,
                                                        thinking: ask.thinking) else {
            return decisions
        }
        guard let video = await VideoWishCheck.classify(asking: {
            try await QwenAPI.askText(request)
        }, fallback: wish) else {
            flowMark("VIDEO-PRUEFUNG nein")
            return decisions
        }
        var changed = decision
        changed.route = .videoCreate(video)
        changed.wish = wish
        flowMark("VIDEO-PRUEFUNG ja dauer=\(video.clampedDuration)s")
        return [changed]
    }

}

@MainActor
struct SystemRouterSteps: RouterStepPlanning {
    func steps(_ ask: RouterAsk) async -> [ToolDecision] { await ToolRouter.stepsImpl(ask) }
}
