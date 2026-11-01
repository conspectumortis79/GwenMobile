import GwenMobileKit
import Foundation

enum WishRouting {
    static let stagger = Duration.milliseconds(350)
    static let inFlight = 3
    static let pictureMakers: Set<SendStepKind> = [.create, .gallery, .edit]
    static let pictureCandidates: Set<SendStepKind> = [.create, .chat, .gallery, .edit]
    static let oneWishMultipleSteps: [SendStepKind] = [.memory, .calendar]

    typealias Asking = @Sendable (_ index: Int, _ wish: String, _ offersEdit: Bool) async throws -> Data

    static func chosen(wishes: [String]?, whole: [ToolDecision], routed: [ToolDecision]) -> [ToolDecision] {
        guard let wishes else { return whole }
        guard wishes.count > 1 else {
            if whole.count > 1,
               whole.allSatisfy({ oneWishMultipleSteps.contains($0.stepKind) }) { return whole }
            return Array(whole.prefix(1))
        }
        guard !routed.isEmpty else { return whole }
        guard whole.count == routed.count else { return routed }
        return zip(whole, routed).map { wholeDecision, routedDecision in
            if routedDecision.stepKind == .chat, wholeDecision.stepKind != .chat {
                var kept = wholeDecision
                kept.wish = routedDecision.wish
                kept.standalone = routedDecision.standalone
                return kept
            }
            guard wholeDecision.stepKind == routedDecision.stepKind,
                  case .reminder(let routedRequest) = routedDecision.route,
                  case .reminder(let wholeRequest) = wholeDecision.route else {
                return routedDecision
            }
            var kept = routedDecision
            kept.route = .reminder(ReminderMerge.merged(routedRequest, with: wholeRequest))
            return kept
        }
    }

    static func applyingVideoWishes(_ decisions: [ToolDecision], parts: [WishPart]?) -> [ToolDecision] {
        guard let parts, parts.count == decisions.count else { return decisions }
        return zip(decisions, parts).map { decision, part in
            guard part.isVideo, decision.stepKind != .video else { return decision }
            guard decision.stepKind == .chat || decision.stepKind == .create else { return decision }
            let request = VideoRequest(prompt: part.text,
                                       duration: part.videoSeconds ?? VideoRequest.defaultDuration,
                                       ratio: part.videoRatio ?? .landscape)
            var video = ToolDecision(route: .videoCreate(request))
            video.wish = part.text
            video.standalone = decision.standalone
            return video
        }
    }

    @MainActor
    static func scoped(_ decisions: [ToolDecision], parts: [WishPart]?,
                       lists: [String] = [],
                       placeExists: (@Sendable @MainActor (String) async -> Bool)? = nil) async -> [ToolDecision] {
        let aligned = parts?.count == decisions.count ? parts : nil
        var result: [ToolDecision] = []
        result.reserveCapacity(decisions.count)
        for (index, decision) in decisions.enumerated() {
            var kept = decision
            if case .reminder(var request) = kept.route {
                if let part = aligned?[index] {
                    if request.list == nil, part.listKnown, let list = part.list,
                       case .title(let name) = ReminderListChoice.resolve(requested: list, available: lists,
                                                                          deviceDefault: nil,
                                                                          silent: .keepCurrent) {
                        request.list = name
                    }
                    if request.place == nil, part.placeKnown, let raw = part.place,
                       let name = await resolvedPlace(raw, placeExists: placeExists) {
                        request.place = ReminderPlace(name: name, proximity: .arrive)
                    }
                }
                if let list = request.list, !lists.isEmpty {
                    if case .title(let name) = ReminderListChoice.resolve(requested: list, available: lists,
                                                                          deviceDefault: nil,
                                                                          silent: .keepCurrent) {
                        request.list = name
                    } else {
                        request.list = nil
                    }
                }
                if let place = request.place {
                    if let name = await resolvedPlace(place.name, placeExists: placeExists) {
                        request.place = ReminderPlace(name: name, proximity: place.proximity)
                    } else if placeExists != nil {
                        request.place = nil
                    }
                }
                kept.route = .reminder(request)
            }
            result.append(kept)
        }
        return result
    }

    @MainActor
    private static func resolvedPlace(_ raw: String,
                                     placeExists: (@Sendable @MainActor (String) async -> Bool)?) async -> String? {
        guard let placeExists else { return nil }
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }
        for candidate in placeCandidates(trimmed) {
            guard await placeExists(candidate) else { continue }
            return candidate
        }
        return nil
    }

    private static func placeCandidates(_ raw: String) -> [String] {
        var result: [String] = []
        var words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while !words.isEmpty {
            let candidate = words.joined(separator: " ")
            if !result.contains(candidate) { result.append(candidate) }
            words.removeFirst()
        }
        return result
    }

    static func routed(_ wishes: [String], independent: Set<Int> = [],
                       asking ask: @escaping Asking) async -> [ToolDecision] {
        guard wishes.count > 1 else { return [] }
        let first = await decide(Array(wishes.indices), wishes: wishes, offersEdit: false, asking: ask)
        var found = wishes.indices.map { first[$0] }
        let again = editCandidates(found)
        if !again.isEmpty {
            let second = await decide(again, wishes: wishes, offersEdit: true, asking: ask)
            for index in again {
                if let decision = second[index] { found[index] = decision }
            }
        }
        let doubted = secondOpinions(found, besides: again)
        if !doubted.isEmpty {
            let second = await decide(doubted, wishes: wishes, offersEdit: false, asking: ask)
            for index in doubted {
                if let decision = second[index], decision.stepKind != .chat { found[index] = decision }
            }
        }
        return wishes.indices.map { index in
            let routedAs = found[index].map { $0.stepKind.rawValue + " " + $0.stepDetail }
                ?? "keine entscheidung, antwort im chat"
            flowMarkPersonal("WUNSCH \(index + 1) \u{2192} \(TextLine.oneLine(routedAs, limit: 160))"
                             + (again.contains(index) ? " bildwerkzeug=ja" : "")
                             + (doubted.contains(index) ? " zweitmeinung=ja" : "")
                             + (independent.contains(index) ? " unabhaengig=ja" : ""))
            var decision = found[index] ?? ToolDecision(route: .chat)
            decision.wish = wishes[index]
            decision.standalone = independent.contains(index)
            return decision
        }
    }

    static func secondOpinions(_ found: [ToolDecision?], besides asked: [Int]) -> [Int] {
        found.indices.filter { index in
            !asked.contains(index) && (found[index].map { $0.stepKind == .chat } ?? true)
        }
    }

    static func editCandidates(_ found: [ToolDecision?]) -> [Int] {
        found.indices.filter { index in
            guard let kind = found[index]?.stepKind, pictureCandidates.contains(kind) else { return false }
            return found.prefix(index).contains { earlier in
                earlier.map { pictureMakers.contains($0.stepKind) } ?? false
            }
        }
    }

    private static func decide(_ indices: [Int], wishes: [String], offersEdit: Bool,
                               asking ask: @escaping Asking) async -> [Int: ToolDecision] {
        await withTaskGroup(of: (Int, ToolDecision?).self) { group in
            var next = 0
            while next < min(inFlight, indices.count) {
                launch(indices[next], wish: wishes[indices[next]], offersEdit: offersEdit,
                       after: stagger * next, into: &group, asking: ask)
                next += 1
            }
            var collected: [Int: ToolDecision] = [:]
            for await item in group {
                if let decision = item.1 { collected[item.0] = decision }
                guard next < indices.count else { continue }
                launch(indices[next], wish: wishes[indices[next]], offersEdit: offersEdit,
                       after: stagger, into: &group, asking: ask)
                next += 1
            }
            return collected
        }
    }

    private static func launch(_ index: Int, wish: String, offersEdit: Bool, after delay: Duration,
                               into group: inout TaskGroup<(Int, ToolDecision?)>, asking ask: @escaping Asking) {
        group.addTask {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return (index, await ToolRouter.plan(asking: { try await ask(index, wish, offersEdit) }).first)
        }
    }

    static func system(_ system: String, wish index: Int, of wishes: [String], offersEdit: Bool) -> String {
        var text = system
        if wishes.count > 1 {
            text += "\n\n" + PromptLibrary.text("wish_context", ["wishes": numbered(wishes),
                                                                 "number": String(index + 1)])
        }
        text += "\n\n" + PromptLibrary.text("wish_single")
        let earlier = wishes.prefix(index)
        guard offersEdit, !earlier.isEmpty else { return text }
        let listed = earlier.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
        text += " " + PromptLibrary.text("wish_single_earlier", ["earlier_wishes": listed])
        return text
    }

    static func answerFocus(_ decision: ToolDecision, among actions: [ToolDecision]) -> String {
        var wishes: [String] = []
        for action in actions where !action.wishText.isEmpty && !wishes.contains(action.wishText) {
            wishes.append(action.wishText)
        }
        guard wishes.count > 1, let index = wishes.firstIndex(of: decision.wishText) else { return "" }
        return PromptLibrary.text("wish_answer", ["wishes": numbered(wishes), "number": String(index + 1),
                                                  "wish": decision.wishText])
    }

    private static func numbered(_ wishes: [String]) -> String {
        wishes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}
