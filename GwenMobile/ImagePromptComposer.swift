import Foundation

enum ImagePromptComposer {
    static let minPromptChars = 12
    static let maxPromptChars = 600

    static let contextSignals = PhraseMatch(phrases: ["davon", "daraus", "damit", "dazu", "darin",
                                                      "der antwort", "deine antwort", "ihre antwort", "dem bild",
                                                      "des bildes", "aus dem bild", "dem foto", "den informationen",
                                                      "diesen informationen", "den zahlen", "diesen zahlen",
                                                      "diesen werten", "den werten", "der tabelle", "den daten",
                                                      "der grafik", "dem diagramm", "wie oben", "wie gesagt",
                                                      "vorher", "vorige", "letzte antwort", "genannt", "erwähnt",
                                                      "this image", "this picture", "this photo", "this data",
                                                      "these numbers", "these values", "from that", "about it",
                                                      "your answer", "the answer", "the chart", "the table",
                                                      "the graphic", "about this", "you said", "mentioned"])

    static func needsConversationContext(_ text: String, history: [ChatMessage]) -> Bool {
        guard history.contains(where: { $0.role == .assistant }) else { return false }
        let lowered = text.lowercased()
        return FollowUpResolver.needsContext(lowered) || contextSignals.matches(lowered)
    }

    static func requestMessages(text: String, history: [ChatMessage]) -> [ChatMessage] {
        FollowUpResolver.requestMessages(text: text, history: history)
    }

    private static let quoteCharacters = CharacterSet(charactersIn: "\"“”'`")

    static func usablePrompt(_ raw: String, insteadOf text: String) -> String? {
        var prompt = stripFences(raw)
        prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= minPromptChars else { return nil }
        guard prompt.lowercased() != original.lowercased() else { return nil }
        guard !FollowUpResolver.refusalSignals.matches(prompt.lowercased()) else { return nil }
        return String(prompt.prefix(maxPromptChars))
    }

    static func instructions() -> String {
        """
        You write the final prompt for an image generation model. That model never sees the conversation, \
        so your prompt has to carry everything the picture needs.
        Reply with ONLY the prompt text, no preamble, no quotes, no markdown fences, at most 500 characters, \
        in the language of the user's request.
        Describe the picture itself: subject, composition, style, colours, mood, and every word, name, number \
        or fact the picture should show. Take those from the KONTEXT block, keep what the NEUE FRAGE adds.
        Never write references to the chat such as "davon", "daraus", "wie oben", "your answer" or \
        "the previous picture" — name what they stand for instead.
        If the NEUE FRAGE is already self-contained, repeat it unchanged.
        """
    }

    private static func stripFences(_ raw: String) -> String {
        var lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let first = lines.first, isFence(first) { lines.removeFirst() }
        if let last = lines.last, isFence(last) { lines.removeLast() }
        return lines.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func isFence(_ line: String) -> Bool {
        guard line.hasPrefix("```") else { return false }
        return line.dropFirst(3).allSatisfy { $0 == "`" || $0.isLetter }
    }
}
