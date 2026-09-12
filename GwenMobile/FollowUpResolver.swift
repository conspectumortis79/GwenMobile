import Foundation

enum FollowUpResolver {
    static let maxQueryChars = 160
    static let selfStandingChars = 34

    static let anaphoraSignals = PhraseMatch(phrases: ["und in", "und die", "und das", "und was", "und wie", "und beim",
                                                       "und obwohl", "was ist damit", "was bedeutet das", "daraus",
                                                       "davon", "dazu", "damit", "darüber", "darueber", "genauer",
                                                       "noch mal", "nochmal", "warum auch", "also doch", "in deutschland",
                                                       "in österreich", "in oesterreich", "in der schweiz", "bei uns",
                                                       "beim letzten", "letzten mal", "deine antwort", "ihre antwort",
                                                       "du meintest", "wie gesagt", "das thema", "gleiche", "ebenso",
                                                       "anderswo", "der zeitverlauf", "im vergleich dazu", "davon ab",
                                                       "what about", "how about", "and in ", "same for", "your answer",
                                                       "you mentioned", "tell me more", "more details", "go deeper",
                                                       "in that case", "back to it", "like you said", "and why",
                                                       "with that", "on this", "about it", "of it", "zum zweiten",
                                                       "zweite frage", "bleiben wir", "daran anknüpf", "daran anknuepf"])

    static let refusalSignals = PhraseMatch(phrases: ["kann ich nicht", "weiß ich nicht", "weiss ich nicht",
                                                      "unknown", "no context", "unable", "ich verstehe nicht"])

    static func needsContext(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return false }
        return anaphoraSignals.matches(t) || t.count < selfStandingChars
    }

    static func requestMessages(text: String, history: [ChatMessage]) -> [ChatMessage] {
        let context = ConversationTranscript.withoutTheNewestQuestion(from: history)
        return [ChatMessage(role: .user, text: "KONTEXT:\n\(context)\n\nNEUE FRAGE:\n\(text)")]
    }

    static func sanitize(_ raw: String) -> String {
        var line = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        for quote in ["\"", "“", "”", "'", "`"] {
            if line.hasPrefix(quote) { line = String(line.dropFirst()) }
            if line.hasSuffix(quote) { line = String(line.dropLast()) }
        }
        for label in ["suchanfrage:", "suchbegriff:", "query:", "frage:", "search:", "rewrite:"]
        where line.lowercased().hasPrefix(label) {
            line = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(line.prefix(maxQueryChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isUsable(_ resolved: String, insteadOf original: String) -> Bool {
        let text = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8, text.count <= maxQueryChars else { return false }
        guard !refusalSignals.matches(text.lowercased()) else { return false }
        return text.lowercased() != original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
