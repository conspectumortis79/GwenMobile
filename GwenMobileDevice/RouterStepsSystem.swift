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
        let now = SystemPrompt.currentDay()
        let system = systemBlock(now: now, context: context,
                                 transcript: ConversationTranscript.withoutTheNewestQuestion(from: history),
                                 catalog: catalog, eraseHistoryWord: eraseHistoryWord,
                                 document: document, watchCatalog: watchCatalog)
        let attachable = !compact && (context.attachedImage || context.rememberedImage)
        let translatesOnDevice = !context.textNeedsTheModel
        let knownLists = ask.reminderLists
        let router = RouterRequestBuilder(baseURL: baseURL, key: key, model: model,
                                          translatesOnDevice: translatesOnDevice, pictures: pictures,
                                          compact: compact, thinking: thinking)
        async let whole = router.plan(text, system: system, attachable: attachable,
                                      parallel: true, label: "ganz")
        async let split = WishSplitter.splitParts(asking: {
            let started = ContinuousClock.now
            defer { flowMark("ROUTER teil=zerlegung dauer_ms=\(msOf(started.duration(to: .now)))") }
            return try await QwenAPI.askText(try WishSplitter.request(baseURL: baseURL, key: key, model: model,
                                                                      text: text, thinking: thinking))
        }, knownLists: knownLists)
        let calls = await whole
        let parts = await split
        let wishes = parts?.map(\.text)
        let listed = wishes ?? []
        let independent = Set((parts ?? []).enumerated().compactMap { $0.element.independent ? $0.offset : nil })
        let routerSplit = WishRouting.routerSplit(calls: calls.count, wishes: listed.count)
        let routed: [ToolDecision]
        if routerSplit {
            flowMark("ROUTER zerlegung=router schritte=\(calls.count) nachfragen=0")
            routed = []
        } else if listed.count > 1 || calls.isEmpty {
            routed = await WishRouting.routed(listed, independent: independent, allowSingle: true) {
                index, wish, offersEdit in
                let focused = WishRouting.system(system, wish: index, of: listed, offersEdit: offersEdit)
                return try await router.fetch(wish, system: focused, attachable: attachable || offersEdit)
            }
        } else {
            routed = []
        }
        let paired = WishRouting.paired(WishRouting.chosen(wishes: wishes, whole: calls, routed: routed),
                                        wishes: listed)
        let chosen = WishRouting.applyingIndependence(independent, to: paired, wishes: listed)
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
            await router.plan(pictureText, system: system + "\n\n" + hint, attachable: attachable)
        }
        if pictureChecked.map(\.stepKind) != videoVerified.map(\.stepKind) {
            flowMark("BILDKETTE geprueft "
                     + "vorher=\(videoVerified.map { $0.stepKind.rawValue }.joined(separator: "+")) "
                     + "nachher=\(pictureChecked.map { $0.stepKind.rawValue }.joined(separator: "+"))")
        }
        let reconciled = await AppointmentReminderCheck.reconciled(pictureChecked, message: text) { wish, hint in
            await router.plan(wish, system: system + "\n\n" + hint, attachable: attachable)
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
            let checks = listed.count <= 1 ? confirmations + [PriceIntentCheck()] : confirmations
            for check in checks {
                let corrected = await check.checked(current, wish: wish) { hint in
                    let rewritten = focused + "\n\n" + hint
                    return await router.plan(wish, system: rewritten, attachable: attachable).first
                }
                current = corrected
                current.standalone = decision.standalone
            }
            checked.append(current)
        }
        checked = await PictureWishMerge.merged(checked) { first, second in
            let firstText = first.wishText.isEmpty ? first.picturePromptText : first.wishText
            let secondText = second.wishText.isEmpty ? second.picturePromptText : second.wishText
            guard !firstText.isEmpty, !secondText.isEmpty,
                  let request = try? PictureWishMerge.request(baseURL: baseURL, key: key, model: model,
                                                              first: firstText, second: secondText,
                                                              thinking: thinking) else { return false }
            let answer = try? await QwenAPI.askText(request)
            return PictureWishMerge.same(answer)
        }
        if checked.isEmpty, let picture = ask.picture {
            let languages = TextRecognizing.languages
            let ocr = await Offload.value { TextRecognizing.recognize(data: picture, languages: languages) }
            let enriched = text + (ocr.map { "\n\nBildtext: \($0)" } ?? "")
            let textOnly = RouterRequestBuilder(baseURL: baseURL, key: key, model: model,
                                                translatesOnDevice: translatesOnDevice, pictures: [],
                                                compact: compact, thinking: thinking)
            let hint = system + "\n\n" + PriceIntentCheck.hint
            if let fallback = await textOnly.plan(enriched, system: hint, attachable: false).first,
               case .priceSearch = fallback.route {
                var kept = fallback
                kept.wish = text
                checked = [kept]
            }
        }
        flowMark("ROUTER dauer_ms=\(msOf(routerStarted.duration(to: .now)))")
        return checked.map { $0.withChatText(excluding: text, history: history) }
    }

    private static func verifyingVideoWish(_ decisions: [ToolDecision], parts: [WishPart]?,
                                           ask: RouterAsk) async -> [ToolDecision] {
        guard ask.videoGenerationAvailable, decisions.count == 1,
              let decision = decisions.first,
              decision.stepKind == .chat else { return decisions }
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

struct RouterRequestBuilder: Sendable {
    let baseURL: String
    let key: String
    let model: String
    let translatesOnDevice: Bool
    let pictures: [Data]
    let compact: Bool
    let thinking: ThinkingDirective

    func fetch(_ text: String, system: String, attachable: Bool,
               parallel: Bool = false) async throws -> Data {
        try await HTTP.jsonData(try request(text, system: system, attachable: attachable, parallel: parallel))
    }

    func plan(_ text: String, system: String, attachable: Bool, parallel: Bool = false,
              label: String? = nil) async -> [ToolDecision] {
        let started = ContinuousClock.now
        defer {
            if let label {
                flowMark("ROUTER teil=\(label) dauer_ms=\(msOf(started.duration(to: .now)))")
            }
        }
        return await ToolRouter.plan(asking: {
            try await fetch(text, system: system, attachable: attachable, parallel: parallel)
        })
    }

    func request(_ text: String, system: String, attachable: Bool,
                 parallel: Bool = false) throws -> URLRequest {
        try ToolRouter.request(baseURL: baseURL, key: key, model: model, text: text, system: system,
                               attachable: attachable, translatesOnDevice: translatesOnDevice,
                               pictures: pictures, parallel: parallel, compact: compact, thinking: thinking)
    }
}

@MainActor
struct SystemRouterSteps: RouterStepPlanning {
    func steps(_ ask: RouterAsk) async -> [ToolDecision] { await ToolRouter.stepsImpl(ask) }
}
