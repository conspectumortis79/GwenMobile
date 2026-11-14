import GwenMobileKit
import Foundation

enum MemoryAnswers {
    static func saved(_ entry: MemoryEntry, merged: Bool) -> String {
        let body = merged ? L.t("memory_saved_updated") : L.t("memory_saved")
        var text = body + "\n\n" + L.fmt("memory_saved_text", entry.text)
        if let due = MemoryStore.dueText(entry) {
            text += "\n" + L.fmt("memory_due_line", due)
        }
        return text
    }

    static func forgot(_ entry: MemoryEntry) -> String {
        L.fmt("memory_forgot", entry.text)
    }

    static func forgetMissing() -> String {
        L.t("memory_forget_missing")
    }

    static func off() -> String {
        L.t("memory_off")
    }

    static func list(_ entries: [MemoryEntry]) -> String {
        guard !entries.isEmpty else { return L.t("memory_list_empty") }
        var counts: [MemoryCategory: Int] = [:]
        for entry in entries { counts[entry.category, default: 0] += 1 }
        var lines: [String] = []
        for category in MemoryCategory.allCases {
            guard let count = counts[category], count > 0 else { continue }
            lines.append("- " + L.t(category.labelKey) + ": " + String(count))
        }
        var text = L.fmt("memory_list_intro", String(entries.count)) + "\n" + lines.joined(separator: "\n")
        let pinned = entries.filter(\.pinned).prefix(3)
        for entry in pinned {
            text += "\n\u{2022} " + entry.text
        }
        return text
    }
}
