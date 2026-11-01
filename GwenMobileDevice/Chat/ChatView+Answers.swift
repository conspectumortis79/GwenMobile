@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func withBusy<T>(_ label: String,
                                        _ work: @MainActor () async -> T) async -> T {
        await busy.running(label, work)
    }

    nonisolated static func sendTrace(decision: ToolDecision) -> String {
        "suchtext=\(decision.searchQuery ?? "-") "
            + "bildtext=\(decision.pictureInstruction ?? decision.picturePrompt ?? "-") "
            + "bildsuchtext=\(decision.pictureQuery ?? "-") "
            + "termin=\(describeAction(decision.calendarAction))"
    }

    nonisolated static func describeAction(_ action: QwenAPI.CalendarPlan.Action?) -> String {
        action.map { String(describing: $0) } ?? "-"
    }

    @discardableResult
    @MainActor func finishAnswer(_ text: String, artifacts: AnswerArtifacts = AnswerArtifacts(),
                                         thinking: ThinkingLevel? = nil, model: String?, convID: UUID,
                                         started: Date, slot: AnswerSlot? = nil,
                                         announce: Bool = true,
                                         preview: Bool = false) -> AnswerPlacement? {
        let piece = AnswerPiece(text: text, artifacts: artifacts, model: model, thinking: thinking,
                                step: slot?.step)
        guard let slot else {
            return appendPlaced(piece, convID: convID, started: started, announce: announce)
        }
        let placement = AnswerPlacement(messageID: nil, slot: slot,
                                        convID: convID, started: started)
        if preview, slot.writes, !(artifacts.outImages ?? []).isEmpty {
            slot.showNow(piece, to: store, convID: convID, started: started)
            placement.settle(slot.writer.messageID)
            slot.commit {
                slot.carry.add(piece)
                slot.writer.forget(step: slot.step)
                slot.writer.flush(to: store, convID: convID, started: started)
            }
            return placement
        }
        slot.commit {
            if slot.store(piece, to: store, convID: convID, started: started) {
                placement.settle(slot.writer.messageID)
                return
            }
            placement.settle(appendPlaced(piece, convID: convID, started: started,
                                          announce: announce)?.messageID)
        }
        return placement
    }

    @discardableResult
    @MainActor private func appendPlaced(_ piece: AnswerPiece, convID: UUID, started: Date,
                                         announce: Bool) -> AnswerPlacement? {
        guard let messageID = store.appendAssistant(piece.text, model: piece.model,
                                                    elapsed: Date().timeIntervalSince(started), to: convID,
                                                    outImages: piece.artifacts.outImages,
                                                    files: piece.artifacts.files,
                                                    sources: piece.artifacts.sources,
                                                    sourcesHeadingKey: piece.artifacts.sourcesHeadingKey,
                                                    sourceReview: piece.artifacts.sourceReview,
                                                    thinking: piece.thinking,
                                                    placeGroups: piece.artifacts.placeGroups,
                                                    fileRefs: piece.artifacts.fileRefs,
                                                    fileRefsHeadingKey: piece.artifacts.fileRefsHeadingKey,
                                                    gallery: piece.artifacts.gallery,
                                                    calendar: piece.artifacts.calendarRef,
                                                    reminder: piece.artifacts.reminderRef,
                                                    memoryRefs: piece.artifacts.memoryRefs,
                                                    weather: piece.artifacts.weatherRef,
                                                    priceWatch: piece.artifacts.priceWatchRef,
                                                    briefing: piece.artifacts.dayBriefingRef)
        else { return nil }
        if announce { announceAnswer(piece.text) }
        return AnswerPlacement(messageID: messageID, slot: nil,
                               convID: convID, started: started)
    }

    @MainActor func appendFailure(_ text: String, model: String?,
                                          convID: UUID, started: Date, slot: AnswerSlot? = nil) {
        guard !Task.isCancelled else { return }
        finishAnswer(text, model: model, convID: convID, started: started, slot: slot, announce: false)
    }

    @MainActor func appendAnswerFailure(_ error: Error, genericKey: String, model: String?,
                                                convID: UUID, started: Date, slot: AnswerSlot? = nil) {
        guard !Task.isCancelled, !isCancellation(error) else { return }
        appendFailure(AnswerError.other(error, model: model, generic: L.t(genericKey)),
                      model: model, convID: convID, started: started, slot: slot)
    }

    @MainActor func appendModelFailure(_ error: Error, model: String?,
                                               convID: UUID, started: Date, slot: AnswerSlot? = nil) {
        guard !Task.isCancelled, !isCancellation(error) else { return }
        appendFailure(AnswerError.model(error, model: model, generic: L.t("err_generic")),
                      model: model, convID: convID, started: started, slot: slot)
    }

    @MainActor private func isCancellation(_ error: Error) -> Bool {
        guard RunStop.isCancellation(error) else { return false }
        flowMarkPersonal("ABBRUCH fehler_verworfen \(TextLine.oneLine(error.localizedDescription, limit: 80))")
        return true
    }

    @MainActor func finishCancelled(_ partial: String?, thinking: ThinkingLevel?, model: String,
                                            convID: UUID, started: Date, slot: AnswerSlot?) {
        let kept = ChatMarkers.strip(partial ?? "").trimmed
        flowMarkPersonal("ABBRUCH stream teil_zeichen=\(kept.count)")
        guard !kept.isEmpty else { return }
        finishAnswer(kept, thinking: thinking, model: model, convID: convID, started: started,
                     slot: slot, announce: false)
    }

    @MainActor func reportChatFailure(_ error: Error, model: String, convID: UUID, started: Date,
                                              slot: AnswerSlot? = nil) {
        appendAnswerFailure(error, genericKey: "err_chat_generic", model: model,
                            convID: convID, started: started, slot: slot)
        guard let api = error as? APIError else { return }
        let friendly = L.friendlyError(api.message, model: model, status: api.status)
        if friendly.openSettings { queueAlert(friendly) }
    }

}
