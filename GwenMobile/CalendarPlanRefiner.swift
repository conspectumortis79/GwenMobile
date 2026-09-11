import Foundation

enum CalendarPlanRefiner {

    static let privateValue = "privat"
    static let workValue = "arbeit"

    static let fillerWords: Set<String> = ["bitte", "der", "die", "das", "den", "dem", "des", "ein", "eine",
                                           "einen", "in", "im", "auf", "nur", "als", "notiz", "nachricht",
                                           "kalender", "termin", "mein", "meine", "meinen", "statt",
                                           "stattdessen", "anstelle", "von", "vom", "zu", "zum", "zur",
                                           "mit", "fur", "uhr", "und", "oder", "nicht", "neuer", "neue"]

    static func category(in text: String) -> String? {
        let folded = CalendarChoice.normalize(text)
        guard !folded.isEmpty else { return nil }
        var best: (offset: Int, value: String)?
        for (hint, value) in hintMap() {
            guard let range = folded.range(of: hint) else { continue }
            let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
            if best == nil || offset < best!.offset { best = (offset, value) }
        }
        return best?.value
    }

    static func isPureCalendarHint(_ text: String) -> Bool {
        let tokens = CalendarChoice.normalize(text)
            .split(whereSeparator: { " .,!?;:-–—".contains($0) })
            .map(String.init)
        guard !tokens.isEmpty, tokens.count <= 5 else { return false }
        let hints = Set(hintMap().map { $0.hint })
        guard tokens.contains(where: { hints.contains($0) }) else { return false }
        return tokens.allSatisfy { hints.contains($0) || fillerWords.contains($0) }
    }

    static func refine(_ plan: QwenAPI.CalendarPlan, instruction: String) -> QwenAPI.CalendarPlan {
        var refined = plan
        if refined.calendar == nil || refined.calendar!.trimmingCharacters(in: .whitespaces).isEmpty {
            refined.calendar = category(in: instruction) ?? category(in: refined.notes ?? "")
        }
        if let notes = refined.notes, isPureCalendarHint(notes) {
            refined.notes = nil
        }
        return refined
    }

    private static func hintMap() -> [(hint: String, value: String)] {
        CalendarChoice.privateHints.map { ($0, privateValue) } + CalendarChoice.workHints.map { ($0, workValue) }
    }
}
