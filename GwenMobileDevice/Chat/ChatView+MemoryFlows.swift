@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runMemoryFlow(_ request: MemoryRequest, convID: UUID, started: Date,
                                          slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        guard settings.memory.enabled else {
            finishAnswer(MemoryAnswers.off(), model: settings.chatModel, convID: convID,
                         started: started, slot: slot, announce: false)
            return
        }
        let model = settings.chatModel
        switch request.action {
        case .suggest:
            guard let text = request.text, !MemoryStore.cleanText(text).isEmpty else { return }
            let suggestion = MemorySuggestion(text: MemoryStore.cleanText(text),
                                              category: request.category ?? .fallback,
                                              anchor: request.date, intervalMonths: request.intervalMonths,
                                              replaceKey: request.replaceKey)
            pendingSuggestions.append(suggestion)
            flowMarkPersonal("GEDÄCHTNIS vorschlag text=\(TextLine.oneLine(suggestion.text, limit: 80)) "
                             + "offen=\(pendingSuggestions.count)")
        case .create:
            guard let text = request.text, !MemoryStore.cleanText(text).isEmpty else { return }
            guard let result = await store.memory.add(text: text,
                                                      category: request.category ?? .fallback,
                                                      source: .explicit, date: request.date,
                                                      intervalMonths: request.intervalMonths,
                                                      replaceKey: request.replaceKey) else { return }
            guard !Task.isCancelled else { return }
            let refs = [MemoryRef(entry: result.entry)].nilIfEmpty
            let answer = MemoryAnswers.saved(result.entry, merged: result.merged)
            flowMarkPersonal("GEDÄCHTNIS gespeichert merged=\(result.merged) key=\(result.entry.shortKey)")
            finishAnswer(answer, artifacts: AnswerArtifacts(memoryRefs: refs), model: model,
                         convID: convID, started: started, slot: slot)
        case .forget:
            guard let entry = await store.memory.entry(key: request.key) else {
                finishAnswer(MemoryAnswers.forgetMissing(), model: model, convID: convID,
                             started: started, slot: slot, announce: false)
                return
            }
            guard !Task.isCancelled else { return }
            await store.memory.delete(key: entry.shortKey)
            guard !Task.isCancelled else { return }
            let answer = MemoryAnswers.forgot(entry)
            flowMarkPersonal("GEDÄCHTNIS vergessen key=\(entry.shortKey)")
            finishAnswer(answer, model: model, convID: convID, started: started, slot: slot)
        case .list:
            let entries = await store.memory.all()
            guard !Task.isCancelled else { return }
            let answer = MemoryAnswers.list(entries)
            let refs = entries.prefix(MemoryStore.catalogLimit).map(MemoryRef.init(entry:)).nilIfEmpty
            finishAnswer(answer, artifacts: AnswerArtifacts(memoryRefs: refs), model: model,
                         convID: convID, started: started, slot: slot)
        }
    }

    @MainActor func runHistoryFlow(convID: UUID, started: Date, slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let model = settings.chatModel
        store.cleaner.deleteAllConversations()
        let answer = L.t("history_deleted")
        flowMarkPersonal("VERLAUF geloescht bereich=alle")
        let target = store.current?.id ?? convID
        finishAnswer(answer, model: model, convID: target, started: started, slot: slot)
    }

    @MainActor func savePendingSuggestions() {
        guard !pendingSuggestions.isEmpty else { return }
        let suggestions = pendingSuggestions
        pendingSuggestions = []
        Task {
            for suggestion in suggestions {
                guard let result = await store.memory.add(suggestion: suggestion,
                                                          source: .suggestion) else { continue }
                flowMarkPersonal("GEDÄCHTNIS vorschlag_gespeichert merged=\(result.merged) "
                                 + "key=\(result.entry.shortKey)")
            }
        }
    }

    @MainActor func dismissPendingSuggestions() {
        pendingSuggestions = []
    }

    @MainActor func checkMemoryDue() async {
        guard !Task.isCancelled else { return }
        guard settings.memory.enabled else { return }
        guard !memoryDueRunning else { return }
        memoryDueRunning = true
        defer { memoryDueRunning = false }
        let due = await store.memory.dueReminders(now: Date())
        guard !Task.isCancelled else { return }
        for entry in due {
            guard !Task.isCancelled else { return }
            if await MemoryNotifier.notify(entry) {
                await store.memory.markNotified(key: entry.shortKey)
                flowMarkPersonal("GEDÄCHTNIS frist faellig key=\(entry.shortKey)")
            } else {
                flowMarkPersonal("GEDÄCHTNIS frist nicht_zugestellt key=\(entry.shortKey)")
            }
        }
    }

}
