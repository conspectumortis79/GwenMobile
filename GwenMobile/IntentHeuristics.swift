import Foundation

struct PhraseMatch: Sendable {
    var phrases: [String]

    func matches(_ lowered: String) -> Bool {
        phrases.contains { lowered.contains($0) }
    }
}

enum IntentHeuristics {
    static let imageCreation = PhraseMatch(phrases: ["erstelle", "erzeuge", "generiere", "zeichne", "male", "kreiere",
                                                     "create", "generate", "draw", "make "])
    static let imageSubject = PhraseMatch(phrases: ["bild", "abbild", "illustration", "foto", "picture", "image",
                                                    "photo", "logo", "poster", "wallpaper"])
    static let calendarTopic = PhraseMatch(phrases: ["termin", "kalender", "appointment", "meeting", "verlege", "versionb",
                                                     "verschieb", "absage", "erinner", "treffen", "geburtstag", "zusage",
                                                     "blocke", "blockier", "freez", "slot", "eintrage", "eintrg", "anlegen",
                                                     "reminder", "schedule", "calendar", "delete the appoint", "cancel the"])
    static let imageEditTopic = PhraseMatch(phrases: ["änder", "veränder", "bearbeit", "färb", "entfern", "wegmach", "lösche",
                                                      "hinzufüg", "ersetze", "mach ", "mache", "gestalte", "retuschier",
                                                      "freistell", " Hintergrund", "style", "color", "colour",
                                                      "edit", "change", "recolor", "recolour", "remove", "erase",
                                                      "replace", "paint", "turn it", "make it", "background"])
    static let safetyRejection = PhraseMatch(phrases: ["datainspectionfailed", "green net", "content_filter"])
    static let contentPolicyRejection = PhraseMatch(phrases: ["content policy", "inappropriate", "safety"])
    static let invalidInput = PhraseMatch(phrases: ["invalidparameter", "invalid_parameter", "invalid input"])
    static let timeoutInterruption = PhraseMatch(phrases: ["timed out", "timeout", "cancelled"])

    static func looksLikeImageRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        return imageCreation.matches(t) && imageSubject.matches(t)
    }

    static func looksLikeCalendarRequest(_ text: String) -> Bool {
        calendarTopic.matches(text.lowercased())
    }

    static func looksLikeEditRequest(_ text: String) -> Bool {
        imageEditTopic.matches(text.lowercased())
    }
}
