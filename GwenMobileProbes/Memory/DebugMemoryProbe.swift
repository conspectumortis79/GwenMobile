@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugMemoryProbe {
    static func routing() async {
        let report = SweepReport(file: "memory_route.txt")
        let create = ToolRouter.map(name: ToolRouter.memoryTool,
                                    arguments: #"{"action":"create","text":"Ich esse kein Fleisch","category":"likes","date":"2026-05-12","intervalMonths":6}"#)
        report.add("CREATE", describe(create))
        let tea = ToolRouter.map(name: ToolRouter.memoryTool,
                                 arguments: #"{"action":"create","text":"Ich mag Ingwer-Tee","category":"likes"}"#)
        let suggest = ToolRouter.map(name: ToolRouter.memoryTool,
                                     arguments: #"{"action":"suggest","text":"Ich mag Kamillentee","category":"likes"}"#)
        report.add("SUGGEST", describe(suggest))
        let forget = ToolRouter.map(name: ToolRouter.memoryTool,
                                    arguments: #"{"action":"forget","key":"abcd1234"}"#)
        report.add("FORGET", describe(forget))
        let list = ToolRouter.map(name: ToolRouter.memoryTool, arguments: #"{"action":"list"}"#)
        report.add("LIST", describe(list))
        let broken = ToolRouter.map(name: ToolRouter.memoryTool, arguments: #"{"action":"dance"}"#)
        report.add("KAPUTT", broken?.stepKind.rawValue ?? "chat")
        let answer = ToolRouter.map(name: ToolRouter.answerTool,
                                    arguments: #"{"memory":["abcd1234"]}"#)
        report.add("ANTWORT", "schluessel=\(answer?.memoryKeys.joined(separator: ",") ?? "-")")
        let plan = SendPlan.forming([create, forget].compactMap { $0 })
        report.add("PLAN", "\(plan.traceLine) schritte=\(plan.actions.count) eine_antwort=\(plan.merges)")
        let facts = SendPlan.forming([create, tea].compactMap { $0 })
        report.add("PLAN_FAKTEN", "\(facts.traceLine) schritte=\(facts.actions.count) "
                   + "schluessel=\(Set(facts.actions.map(\.stepKey)).count)")
        let block = ToolRouter.systemBlock(now: "2026-10-04 16:20", context: SendContext(), transcript: "",
                                           catalog: "[#abcd1234] Ich esse kein Fleisch (preference, pinned)")
        report.add("KATALOG", block.contains("MEMORY CATALOG") && block.contains("abcd1234")
                   ? "im systemblock" : "fehlt")
        flowLog.info("GEDÄCHTNISROUTING fertig")
    }

    static func store() async {
        let report = SweepReport(file: "memory_store.txt")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwen-memory-probe-" + UUID().uuidString)
        let paths = StoragePaths(documents: root.appendingPathComponent("Documents"),
                                 support: root.appendingPathComponent("Support"))
        let store = MemoryStore(paths: paths)
        guard let added = await store.add(text: "Ich esse kein Fleisch", category: .likes,
                                          source: .explicit) else {
            report.add("PERSISTENZ", "leer")
            return
        }
        let reopened = MemoryStore(paths: paths)
        let persisted = await reopened.count()
        report.add("PERSISTENZ", "eintraege=\(persisted) text=\(added.entry.text) schluessel=\(added.entry.shortKey)")
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        guard let dated = await store.add(text: "Ich war beim Zahnarzt", category: .health,
                                          source: .explicit, date: anchor, intervalMonths: 6) else {
            report.add("FRIST", "leer")
            return
        }
        report.add("FRIST", "faellig=\(MemoryStore.dueText(dated.entry) ?? "-") "
                   + "erinnerung=\(dated.entry.remind)")
        await store.setReminder(key: dated.entry.shortKey, remind: true)
        let due = await store.dueReminders(now: (dated.entry.dueDate ?? Date()).addingTimeInterval(86400))
        report.add("ERINNERUNG", "faellige=\(due.count)")
        let block = await store.block(keys: [added.entry.shortKey])
        report.add("BLOCK", block.contains(added.entry.text) ? "eintrag im block" : "eintrag fehlt")
        let mixed = await store.block(keys: [added.entry.shortKey, "unbekannt"])
        report.add("UNBEKANNT", mixed.contains(added.entry.text) ? "bekannter bleibt" : "bekannter fehlt")
        let catalog = await store.catalog()
        report.add("KATALOG", catalog.contains(added.entry.shortKey) ? "schluessel vorhanden" : "schluessel fehlt")
        await store.markUsed(keys: [added.entry.shortKey])
        let used = await store.all().first { $0.id == added.entry.id }?.useCount ?? -1
        report.add("NUTZUNG", "zaehler=\(used)")
        await store.delete(key: added.entry.shortKey)
        report.add("LOESCHEN", "rest=\(await store.count())")
        let corruptPaths = StoragePaths(documents: root.appendingPathComponent("CorruptDocuments"),
                                        support: root.appendingPathComponent("CorruptSupport"))
        try? FileManager.default.createDirectory(at: corruptPaths.support, withIntermediateDirectories: true)
        try? Data("kein json".utf8).write(to: corruptPaths.memory)
        let corruptStore = MemoryStore(paths: corruptPaths)
        _ = await corruptStore.count()
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: corruptPaths.support.path))?
            .filter { $0.hasPrefix(corruptPaths.memory.lastPathComponent + ".corrupt-") } ?? []
        let backupContent = backups.first.flatMap {
            try? Data(contentsOf: corruptPaths.support.appendingPathComponent($0))
        }
        report.add("KORRUPT_SICHERUNG", "dateien=\(backups.count) inhalt="
                   + (backupContent.map { String(decoding: $0, as: UTF8.self) } ?? "-"))
        let chatPaths = StoragePaths(documents: root.appendingPathComponent("ChatDocuments"),
                                     support: root.appendingPathComponent("ChatSupport"))
        let chat = ChatStore(media: MediaStore(paths: chatPaths), paths: chatPaths)
        await MemoryEditorSheet.commit(store: chat, entry: nil, text: "Wichtiger Merksatz",
                                       category: .likes, pinned: true, remind: false)
        let editorPinned = await chat.memory.all().first?.pinned ?? false
        report.add("EDITOR_PINNED", editorPinned ? "gesetzt" : "fehlt")
        try? FileManager.default.removeItem(at: root)
        flowLog.info("GEDÄCHTNISSPEICHER fertig")
    }

    private static func describe(_ decision: ToolDecision?) -> String {
        guard let decision else { return "kein aufruf" }
        guard case .memory(let request) = decision.route else { return decision.stepKind.rawValue }
        return "\(request.action.rawValue) text=\(request.text ?? "-") kategorie=\(request.category?.rawValue ?? "-") "
            + "schluessel=\(request.key ?? "-") datum=\(request.date.map { Formatters.systemDate($0) } ?? "-")"
    }
}
#endif
