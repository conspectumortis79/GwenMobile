import GwenMobileKit
import Foundation

struct AnswerArtifacts: Equatable {
    var outImages: [Attachment]?
    var files: [AttachedFile]?
    var sources: [WebSource]?
    var sourcesHeadingKey: String?
    var sourceReview: SourceReview?
    var placeGroups: [PlaceGroup]?
    var fileRefs: [FileRef]?
    var fileRefsHeadingKey: String?
    var gallery: PictureGallery?
    var calendarRef: CalendarRef?
    var reminderRef: ReminderRef?
    var memoryRefs: [MemoryRef]?
    var weatherRef: WeatherRef?
    var priceWatchRef: PriceWatchRef?
    var dayBriefingRef: DayBriefingRef?

    func merged(with newer: AnswerArtifacts) -> AnswerArtifacts {
        var kept = self
        func pick<T>(_ old: T?, _ fresh: T?) -> T? { fresh ?? old }
        func joined<T>(_ old: [T]?, _ fresh: [T]?) -> [T]? {
            let all = (old ?? []) + (fresh ?? [])
            return all.isEmpty ? nil : all
        }
        let earlierSources = kept.sources?.count ?? 0
        kept.outImages = joined(kept.outImages, newer.outImages)
        kept.files = joined(kept.files, newer.files)
        kept.sources = joined(kept.sources, newer.sources)
        kept.sourcesHeadingKey = pick(kept.sourcesHeadingKey, newer.sourcesHeadingKey)
        kept.sourceReview = pick(kept.sourceReview,
                                 newer.sourceReview?.shifted(by: earlierSources, sources: newer.sources?.count ?? 0))
        kept.placeGroups = PlaceGroup.combined(kept.placeGroups, newer.placeGroups)
        let knownRefs = kept.fileRefs ?? []
        kept.fileRefs = joined(kept.fileRefs, newer.fileRefs?.filter { !knownRefs.contains($0) })
        kept.fileRefsHeadingKey = pick(kept.fileRefsHeadingKey, newer.fileRefsHeadingKey)
        kept.gallery = pick(kept.gallery, newer.gallery)
        kept.calendarRef = pick(kept.calendarRef, newer.calendarRef)
        kept.reminderRef = pick(kept.reminderRef, newer.reminderRef)
        let knownMemory = kept.memoryRefs ?? []
        kept.memoryRefs = joined(kept.memoryRefs, newer.memoryRefs?.filter { !knownMemory.contains($0) })
        kept.weatherRef = pick(kept.weatherRef, newer.weatherRef)
        kept.priceWatchRef = pick(kept.priceWatchRef, newer.priceWatchRef)
        kept.dayBriefingRef = pick(kept.dayBriefingRef, newer.dayBriefingRef)
        return kept
    }
}

struct AnswerPiece: Equatable {
    var text: String
    var artifacts: AnswerArtifacts = AnswerArtifacts()
    var model: String?
    var thinking: ThinkingLevel?
    var step: Int?
}

@MainActor
final class AnswerCarry {
    private(set) var pieces: [AnswerPiece] = []
    private(set) var planned: [String] = []
    private(set) var created: [CalendarRef] = []

    var hasPlannedAppointment: Bool { !planned.isEmpty }

    var plannedText: String { planned.joined(separator: "\n") }

    var lastAnswerText: String { pieces.last(where: { !$0.text.trimmed.isEmpty })?.text ?? "" }

    func freshPieces(since index: Int) -> [AnswerPiece] {
        let start = min(max(index, 0), pieces.count)
        return Array(pieces[start...])
    }

    func text(since index: Int) -> String {
        let start = min(max(index, 0), pieces.count)
        var earlierSources = pieces[..<start].reduce(0) { $0 + ($1.artifacts.sources?.count ?? 0) }
        var parts: [String] = []
        for piece in pieces[start...] {
            let own = piece.artifacts.sources?.count ?? 0
            parts.append(CitationMarkers.shifted(piece.text, by: earlierSources, sources: own))
            earlierSources += own
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func notePlanned(_ line: String, ref: CalendarRef? = nil) {
        let trimmed = line.trimmed
        if !trimmed.isEmpty { planned.append(trimmed) }
        if let ref { created.append(ref) }
    }

    func createdAppointment(named words: String) -> Bool {
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return created.contains { CalendarPlanRefiner.sameAppointment($0.title, words) }
    }

    func createdAlready(_ plan: QwenAPI.CalendarPlan) -> Bool {
        guard let start = plan.startDate else { return createdAppointment(named: plan.title ?? "") }
        return created.contains { $0.start == start && CalendarPlanRefiner.sameAppointment($0.title, plan.eventTitle) }
    }

    var isEmpty: Bool { pieces.isEmpty }

    var text: String { text(since: 0) }

    var artifacts: AnswerArtifacts {
        pieces.reduce(AnswerArtifacts()) { $0.merged(with: $1.artifacts) }
    }

    var model: String? { pieces.last?.model }
    var thinking: ThinkingLevel? { pieces.last?.thinking }

    @discardableResult
    func add(_ piece: AnswerPiece) -> Int? {
        let trimmed = piece.text.trimmed
        guard !trimmed.isEmpty || piece.artifacts != AnswerArtifacts() else { return nil }
        var stored = piece
        stored.text = trimmed
        pieces.append(stored)
        return pieces.count - 1
    }

    @discardableResult
    func setSourceReview(_ review: SourceReview, forStep step: Int?) -> Bool {
        guard let step, let index = pieces.firstIndex(where: { $0.step == step }) else { return false }
        pieces[index].artifacts.sourceReview = review
        return true
    }
}

@MainActor
final class ChainMessageWriter {
    let carry = AnswerCarry()
    private(set) var messageID: UUID?
    private var spoken = ""
    private var queued: [Int: [@MainActor () -> Void]] = [:]
    private var finished: Set<Int> = []
    private var next = 0
    private var arrived: [Int: AnswerPiece] = [:]

    func showNow(step: Int, _ piece: AnswerPiece, to store: ChatStore, convID: UUID, started: Date) {
        var stored = piece
        stored.step = step
        arrived[step] = stored
        flush(to: store, convID: convID, started: started)
    }

    func forget(step: Int) {
        arrived.removeValue(forKey: step)
    }

    func commit(step: Int, _ write: @MainActor @escaping () -> Void) {
        guard step >= next else {
            write()
            return
        }
        queued[step, default: []].append(write)
        drain()
    }

    func finish(step: Int) {
        finished.insert(step)
        drain()
    }

    func close(upTo count: Int) {
        finished.formUnion(0..<max(0, count))
        drain()
    }

    private func drain() {
        while true {
            while let writes = queued.removeValue(forKey: next), !writes.isEmpty {
                for write in writes { write() }
            }
            guard finished.contains(next) else { return }
            next += 1
            finished.remove(next - 1)
        }
    }

    func flush(to store: ChatStore, convID: UUID, started: Date) {
        guard !carry.isEmpty || !arrived.isEmpty else { return }
        let made = carriedMessage(started: started)
        if let id = messageID {
            store.replaceAssistant(id, in: convID, with: made)
            return
        }
        guard store.appendMessage(made, to: convID) else { return }
        messageID = made.id
    }

    private func carriedMessage(started: Date) -> ChatMessage {
        let shown = arrived.keys.sorted().compactMap { arrived[$0] }
        var held = carry.artifacts
        for piece in shown { held = held.merged(with: piece.artifacts) }
        let early = shown.first
        return ChatMessage(role: .assistant, text: carry.text,
                           model: carry.model ?? early?.model,
                           elapsed: Date().timeIntervalSince(started),
                           outImages: held.outImages, sources: held.sources,
                           sourcesHeadingKey: held.sourcesHeadingKey,
                           sourceReview: held.sourceReview,
                           thinking: carry.thinking ?? early?.thinking, placeGroups: held.placeGroups,
                           files: held.files ?? [],
                           fileRefs: held.fileRefs, fileRefsHeadingKey: held.fileRefsHeadingKey,
                           gallery: held.gallery, calendarRef: held.calendarRef, reminderRef: held.reminderRef,
                           memoryRefs: held.memoryRefs, weatherRef: held.weatherRef,
                           priceWatchRef: held.priceWatchRef, dayBriefingRef: held.dayBriefingRef)
    }

    func speakNext(_ speech: (String) -> Void) {
        let whole = carry.text
        guard whole.count > spoken.count else { return }
        let fresh = String(whole.dropFirst(spoken.count)).trimmed
        spoken = whole
        if !fresh.isEmpty { speech(fresh) }
    }
}

@MainActor
struct AnswerSlot {
    let writer: ChainMessageWriter
    var writes: Bool = true
    var step: Int = 0

    var carry: AnswerCarry { writer.carry }

    func commit(_ write: @MainActor @escaping () -> Void) {
        writer.commit(step: step, write)
    }

    func showNow(_ piece: AnswerPiece, to store: ChatStore, convID: UUID, started: Date) {
        guard writes else { return }
        writer.showNow(step: step, piece, to: store, convID: convID, started: started)
    }

    @discardableResult
    func store(_ piece: AnswerPiece, to store: ChatStore, convID: UUID, started: Date) -> Bool {
        var stored = piece
        if stored.step == nil { stored.step = step }
        writer.carry.add(stored)
        guard writes else { return false }
        writer.flush(to: store, convID: convID, started: started)
        return true
    }
}

@MainActor
final class AnswerPlacement {
    private(set) var messageID: UUID?
    let slot: AnswerSlot?
    let convID: UUID
    let started: Date

    private var settled: Bool
    private var waiting: [CheckedContinuation<UUID?, Never>] = []

    init(messageID: UUID?, slot: AnswerSlot? = nil,
         convID: UUID, started: Date) {
        self.messageID = messageID
        self.slot = slot
        self.convID = convID
        self.started = started
        self.settled = messageID != nil
    }

    func settle(_ messageID: UUID?) {
        guard !settled else { return }
        settled = true
        self.messageID = messageID
        let waiting = self.waiting
        self.waiting = []
        for continuation in waiting { continuation.resume(returning: messageID) }
    }

    func resolvedMessageID() async -> UUID? {
        if settled { return messageID }
        return await withCheckedContinuation { waiting.append($0) }
    }

    @discardableResult
    func applySourceReview(_ review: SourceReview, to store: ChatStore) -> Bool {
        if let slot, slot.writes, slot.carry.setSourceReview(review, forStep: slot.step) {
            slot.writer.flush(to: store, convID: convID, started: started)
            return true
        }
        guard let messageID else { return false }
        return store.updateSourceReview(review, messageID: messageID, in: convID)
    }
}
