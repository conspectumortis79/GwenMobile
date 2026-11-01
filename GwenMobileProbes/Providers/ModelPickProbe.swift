@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum ModelPickProbe {
    static let reportFile = "model_pick.txt"

    static let vendorLimit = 3

    private struct ModelGroup {
        let name: String
        let models: [String]
    }

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let settings = view.settings
        let originalChat = settings.chatModel
        guard settings.isConfigured else {
            report.add("ABBRUCH", "kein anbieter konfiguriert")
            return
        }
        if settings.availableModels.isEmpty {
            try? await settings.reloadModels()
        }
        let groups = groups(models: ModelFilter.textCandidates(settings.availableModels),
                           fallback: settings.provider.rawValue)
        let candidates = select(groups: groups, current: originalChat)
        report.add("GRUPPEN", groups.map { "\($0.name)=\($0.models.count)" }.joined(separator: " "))
        report.add("KONFIG", "anbieter=\(settings.provider.rawValue) chat=\(originalChat) "
                   + "modelle=\(settings.availableModels.count) gruppen=\(groups.count) kandidaten=\(candidates.count) "
                   + "liste=\(candidates.joined(separator: ","))")
        guard !candidates.isEmpty else {
            report.add("ABBRUCH", "keine kandidaten in der modellliste")
            return
        }
        var best: (model: String, right: Int, ms: Int)?
        for model in candidates {
            let result = await benchmark(view, model: model)
            report.add("MODELL", "\(model) richtig=\(result.right)/\(DebugReminderProbe.flowSentences.count) "
                       + "fehler=\(result.failures.map(String.init).joined(separator: ",")) ms=\(result.ms)")
            if best == nil || result.right > best!.right
                || (result.right == best!.right && result.ms < best!.ms) {
                best = (model, result.right, result.ms)
            }
        }
        if let best {
            settings.chatModel = best.model
            ProbeSettingsGuard.keepProfiles = true
            report.add("ANGEWENDET", "chat=\(best.model) vorher=\(originalChat) "
                       + "richtig=\(best.right)/\(DebugReminderProbe.flowSentences.count) ms=\(best.ms)")
        } else {
            settings.chatModel = originalChat
        }
        flowLog.info("MODELLAUSWAHL fertig")
    }

    private static func groups(models: [String], fallback: String) -> [ModelGroup] {
        let usable = models.filter { !$0.lowercased().contains(":free") }
        let grouped = Dictionary(grouping: usable, by: { vendor(of: $0, fallback: fallback) })
        return grouped.keys.sorted().map { ModelGroup(name: $0, models: grouped[$0, default: []].sorted()) }
    }

    static func vendor(of model: String, fallback: String) -> String {
        guard let slash = model.firstIndex(of: "/") else { return fallback }
        let prefix = model[model.startIndex..<slash]
        return prefix.isEmpty ? fallback : String(prefix)
    }

    private static func select(groups: [ModelGroup], current: String) -> [String] {
        var picked: [String] = []
        for group in groups {
            for model in spread(group.models, limit: vendorLimit) where !picked.contains(model) {
                picked.append(model)
            }
        }
        if !current.isEmpty, !picked.contains(current) { picked.insert(current, at: 0) }
        return picked
    }

    private static func spread(_ models: [String], limit: Int) -> [String] {
        guard limit > 1, models.count > limit else { return models }
        let indexes = (0..<limit).map { $0 * (models.count - 1) / (limit - 1) }
        var picked: [String] = []
        for index in indexes where !picked.contains(models[index]) {
            picked.append(models[index])
        }
        return picked
    }

    private static func benchmark(_ view: ChatView,
                                  model: String) async -> (right: Int, failures: [Int], ms: Int) {
        let settings = view.settings
        settings.chatModel = model
        let store = ProbeReminderStore()
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        view.reminderDesk.stand(in: store, places: ProbePlaceLookup())
        let started = ContinuousClock.now
        var right = 0
        var failures: [Int] = []
        for (index, sentence) in DebugReminderProbe.flowSentences.enumerated() {
            let answer = await view.ask(sentence, fresh: true)
            if DebugReminderProbe.flowFits(index, store: store, answer: answer) {
                right += 1
            } else {
                failures.append(index + 1)
            }
        }
        let ms = msOf(started.duration(to: .now))
        view.reminderDesk.restore()
        _ = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        return (right, failures, ms)
    }
}
#endif
