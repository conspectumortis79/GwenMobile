import GwenMobileKit
import Foundation

enum SendStepKind: String, Equatable, CaseIterable {
    case chat
    case search
    case gallery
    case code
    case edit
    case create
    case video
    case translate
    case scan
    case calendar
    case reminder
    case timer
    case readAloud
    case readAnswer
    case place
    case route
    case price
    case priceWatch
    case briefing
    case call
    case clock
    case music
    case message
    case memory
    case history
    case weather
    case status
}

extension ToolDecision {
    var stepKind: SendStepKind {
        switch route {
        case .chat: return searchQuery == nil ? .chat : .search
        case .pictureSearch: return .gallery
        case .code: return .code
        case .imageEdit: return .edit
        case .imageCreate: return .create
        case .videoCreate: return .video
        case .translate: return .translate
        case .scanDocument: return .scan
        case .calendar: return .calendar
        case .reminder: return .reminder
        case .timer: return .timer
        case .readAloud: return .readAloud
        case .readAnswer: return .readAnswer
        case .nearbyPlace: return .place
        case .routeToPlace: return .route
        case .priceSearch: return .price
        case .priceWatch: return .priceWatch
        case .dayBriefing: return .briefing
        case .call: return .call
        case .clock: return .clock
        case .music: return .music
        case .message: return .message
        case .memory: return .memory
        case .history: return .history
        case .weather: return .weather
        case .appStatus: return .status
        }
    }

    var stepDetail: String {
        switch route {
        case .chat: return searchQuery ?? ""
        case .pictureSearch(let query): return query
        case .code(let language): return language.rawValue
        case .translate(let job):
            return [job.targetCode, job.sourceCode ?? "", job.text]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .scanDocument(let request): return request.stepWords
        case .imageEdit: return pictureInstruction ?? ""
        case .imageCreate: return picturePrompt ?? ""
        case .videoCreate(let request): return request.stepWords
        case .calendar: return calendarPlan?.stepWords ?? ""
        case .reminder(let request): return request.stepWords
        case .timer(let request): return request.stepWords
        case .readAloud(let request): return request.stepWords
        case .readAnswer: return "letzte_antwort"
        case .nearbyPlace(let terms, let mode): return terms.joined(separator: " ") + " " + mode.rawValue
        case .routeToPlace(let terms, let mode): return terms.joined(separator: " ") + " " + mode.rawValue
        case .priceSearch(let terms, let country, let nearby):
            return terms.joined(separator: " ") + " " + (country ?? "") + (nearby ? " nah" : "")
        case .priceWatch(let request): return request.stepWords
        case .dayBriefing(let request): return request.stepWords
        case .call(let request): return request.stepWords
        case .clock(let request): return request.stepWords
        case .music(let request): return request.stepWords
        case .message(let request): return request.stepWords
        case .memory(let request):
            return [request.action.rawValue, request.text, request.key, request.replaceKey]
                .compactMap { $0 }
                .joined(separator: " ")
        case .history: return "alle"
        case .weather(let request):
            let when = request.date ?? request.offset.map { "+\($0)d" } ?? request.day.rawValue
            return (request.place ?? "hier") + " " + when
        case .appStatus: return "lokal"
        }
    }

    var stepKey: String {
        let own = plannedFromItsWish && !wishText.isEmpty ? "|" + Self.keyWords(wishText) : ""
        return stepKind.rawValue + "|" + Self.keyWords(stepDetail) + own
    }

    var plannedFromItsWish: Bool { stepKind == .calendar || stepKind == .code }

    private static func keyWords(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var needsExistingEvent: Bool {
        guard case .calendar = route else { return false }
        return calendarPlan?.needsExistingEvent ?? false
    }

    var pictureInstructionText: String {
        pictureInstruction?.trimmed ?? ""
    }

    var picturePromptText: String {
        picturePrompt?.trimmed ?? ""
    }

    var wishText: String {
        wish?.trimmed ?? ""
    }

    func ownWords(or message: String) -> String {
        wishText.isEmpty ? message : wishText
    }

    func pictureText(_ rewritten: String, message: String) -> String {
        guard !wishText.isEmpty else { return rewritten.isEmpty ? message : rewritten }
        return rewritten.isEmpty ? wishText : wishText + "\n\n" + rewritten
    }

    func canRunAsPictureStep(number: Int) -> Bool {
        guard number > 1, wishText.isEmpty else { return true }
        switch stepKind {
        case .edit: return pictureMonochrome || !pictureInstructionText.isEmpty
        case .create: return !picturePromptText.isEmpty
        default: return true
        }
    }

    var mergesIntoOneAnswer: Bool {
        switch stepKind {
        case .price, .priceWatch, .briefing, .video, .translate, .call, .music, .readAnswer, .memory, .history, .weather, .status: return false
        default: return true
        }
    }

    var fillsOneSlot: Bool {
        switch stepKind {
        case .gallery, .calendar, .reminder, .timer, .readAloud, .place, .route, .search, .message: return true
        default: return false
        }
    }
}

struct SendPlan: Equatable {
    let actions: [ToolDecision]

    static let singleChat = SendPlan(actions: [ToolDecision(route: .chat)])

    var primary: ToolDecision { actions.first ?? ToolDecision(route: .chat) }

    var merges: Bool {
        guard actions.count > 1, actions.allSatisfy({ $0.mergesIntoOneAnswer }) else { return false }
        let single = actions.filter { $0.fillsOneSlot }.map { $0.stepKind }
        return Set(single).count == single.count
    }

    var traceLine: String {
        actions.map { $0.stepKind.rawValue }.joined(separator: "+")
    }

    static func forming(_ calls: [ToolDecision]) -> SendPlan {
        var kept: [ToolDecision] = []
        var seen: Set<String> = []
        for action in calls {
            guard !seen.contains(action.stepKey) else { continue }
            if action.stepKind == .call, kept.contains(where: { $0.stepKind == .call }) { continue }
            seen.insert(action.stepKey)
            kept.append(action)
        }
        if kept.count > 1 {
            kept = kept.filter { $0.canRunAsPictureStep(number: 2) }
        }
        kept = mergingRemindersAtOnePlace(kept)
        kept = mergingPriceWatches(kept)
        if kept.isEmpty { return SendPlan(actions: [ToolDecision(route: .chat)]) }
        let late: [SendStepKind] = [.message, .music, .call]
        var early = kept.filter { !late.contains($0.stepKind) }
        early = ordered(early)
        early = absorbingReminderIntoScan(early)
        return SendPlan(actions: early + late.flatMap { kind in kept.filter { $0.stepKind == kind } })
    }

    private static func absorbingReminderIntoScan(_ steps: [ToolDecision]) -> [ToolDecision] {
        var kept = steps
        var index = 0
        while index < kept.count {
            guard case .scanDocument(let scan) = kept[index].route else {
                index += 1
                continue
            }
            var merged = scan
            if index + 1 < kept.count, isScanReminder(kept[index + 1]) {
                merged.remind = true
                kept[index].route = .scanDocument(merged)
                kept.remove(at: index + 1)
                index += 1
                continue
            }
            if index > 0, isScanReminder(kept[index - 1]) {
                merged.remind = true
                kept[index].route = .scanDocument(merged)
                kept.remove(at: index - 1)
                continue
            }
            index += 1
        }
        return kept
    }

    private static func isScanReminder(_ step: ToolDecision) -> Bool {
        guard case .reminder(let request) = step.route else { return false }
        return request.action == .create && request.due == nil && request.minutes == nil
            && request.seconds == nil && request.place == nil
    }

    private static func mergingPriceWatches(_ steps: [ToolDecision]) -> [ToolDecision] {
        var kept: [ToolDecision] = []
        for step in steps {
            guard case .priceWatch(let request) = step.route, request.action == .create,
                  request.key == nil,
                  let index = kept.firstIndex(where: { candidate in
                      guard case .priceWatch(let earlier) = candidate.route, earlier.action == .create,
                            earlier.key == nil, earlier.goal == request.goal else { return false }
                      return sameProduct(earlier.terms, request.terms)
                  }),
                  case .priceWatch(let earlier) = kept[index].route else {
                kept.append(step)
                continue
            }
            var merged = earlier
            merged.terms = PriceWatch.cleanTerms(earlier.terms + request.terms)
            if merged.intervalHours == nil { merged.intervalHours = request.intervalHours }
            if merged.country == nil { merged.country = request.country }
            kept[index].route = .priceWatch(merged)
        }
        return kept
    }

    private static func sameProduct(_ left: [String], _ right: [String]) -> Bool {
        guard let first = left.first, let second = right.first else { return false }
        let a = PriceWatch.fold(first)
        let b = PriceWatch.fold(second)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.contains(b) || b.contains(a) { return true }
        let leftWords = a.split(separator: " ").map(String.init)
        let rightWords = b.split(separator: " ").map(String.init)
        let shared = zip(leftWords, rightWords).prefix { $0 == $1 }.count
        return shared >= 3
    }

    private static func mergingRemindersAtOnePlace(_ steps: [ToolDecision]) -> [ToolDecision] {
        var kept: [ToolDecision] = []
        for step in steps {
            guard case .reminder(let request) = step.route, request.action == .create, let place = request.place,
                  let index = kept.firstIndex(where: { candidate in
                      guard case .reminder(let earlier) = candidate.route, earlier.action == .create else {
                          return false
                      }
                      return earlier.place == place && earlier.due == request.due && earlier.list == request.list
                          && earlier.repeatRule == request.repeatRule && earlier.priority == request.priority
                  }),
                  case .reminder(let earlier) = kept[index].route
            else {
                kept.append(step)
                continue
            }
            var merged = earlier
            merged.title = ReminderTitle.merged([earlier.title, request.title])
            if let notes = request.notes, !notes.isEmpty {
                merged.notes = [earlier.notes, notes].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            kept[index].route = .reminder(merged)
        }
        return kept
    }

    private static func ordered(_ steps: [ToolDecision]) -> [ToolDecision] {
        let waiting = steps.filter { $0.needsExistingEvent }
        let made = steps.filter { !$0.needsExistingEvent }
        guard made.allSatisfy({ $0.wishText.isEmpty }) else { return made + waiting }
        guard let galleryAt = made.firstIndex(where: { $0.stepKind == .gallery }) else {
            return made + waiting
        }
        let before = made.prefix(galleryAt)
        let earlyEdits = before.filter { $0.stepKind == .edit }
        guard !earlyEdits.isEmpty else { return made + waiting }
        let kept = before.filter { $0.stepKind != .edit }
        return kept + [made[galleryAt]] + earlyEdits + made[(galleryAt + 1)...] + waiting
    }
}
