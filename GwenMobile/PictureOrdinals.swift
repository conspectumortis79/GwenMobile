import Foundation

enum PictureOrdinals {
    private static let numberWords: [(word: String, place: Int)] = [
        ("erster", 1), ("erste", 1), ("ersten", 1), ("erstes", 1), ("first", 1),
        ("zweiter", 2), ("zweite", 2), ("zweiten", 2), ("zweites", 2), ("second", 2),
        ("dritter", 3), ("dritte", 3), ("dritten", 3), ("drittes", 3), ("third", 3),
        ("vierter", 4), ("vierte", 4), ("vierten", 4), ("viertes", 4), ("fourth", 4),
        ("fünfter", 5), ("fünfte", 5), ("fünften", 5), ("fünftes", 5), ("fifth", 5),
        ("funfter", 5), ("funfte", 5), ("funften", 5), ("funftes", 5),
        ("sechster", 6), ("sechste", 6), ("sechsten", 6), ("sechstes", 6), ("sixth", 6),
        ("siebenter", 7), ("siebente", 7), ("siebenten", 7), ("siebter", 7), ("siebte", 7),
        ("siebten", 7), ("siebtes", 7), ("seventh", 7),
        ("achter", 8), ("achte", 8), ("achten", 8), ("achtes", 8), ("eighth", 8),
        ("neunter", 9), ("neunte", 9), ("neunten", 9), ("neuntes", 9), ("ninth", 9),
        ("zehnter", 10), ("zehnte", 10), ("zehnten", 10), ("zehntes", 10), ("tenth", 10),
    ]

    private static let pattern = "(?:erste[rn]?|erstes|zweite[rn]?|zweites|dritte[rn]?|drittes|"
        + "vierte[rn]?|viertes|f[üu]nfte[rn]?|f[üu]nftes|sechste[rn]?|sechstes|"
        + "sieb[e]nte[rn]?|siebte[rn]?|siebtes|achte[rn]?|achtes|neunte[rn]?|neuntes|"
        + "zehnte[rn]?|zehntes|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)"
        + "[^\\p{L}]{1,3}(?:[\\p{L}]{1,14}[^\\p{L}]{1,3}){0,2}?"
        + "(?:fotos?|bild(?:er|es)?|aufnahmen?|pictures?|photos?|images?)"
        + "|(?:fotos?|bild(?:er|es)?|aufnahmen?|pictures?|photos?|images?)[^\\p{L}\\d]{1,3}\\d{1,2}(?![\\p{L}\\d])"

    private static let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    static func places(in text: String, total: Int) -> [Int] {
        guard !text.isEmpty, total > 0, let regex else { return [] }
        let ns = text as NSString
        var found: [Int] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let place = place(of: ns.substring(with: match.range)), (1...total).contains(place) else {
                return []
            }
            if found.contains(place) { return [] }
            found.append(place)
        }
        return found
    }

    static func bild(of place: Int, shown: [Int]) -> Int? {
        guard let index = shown.firstIndex(of: place) else { return nil }
        return index + 1
    }

    static func outOfSelection(places: [Int], shown: [Int]) -> Bool {
        places.contains { bild(of: $0, shown: shown) == nil }
    }

    static func numbers(of places: [Int], shown: [Int]) -> [Int] {
        places.compactMap { bild(of: $0, shown: shown) }
    }

    static func hint(places: [Int], shown: [Int], binding: Bool = false) -> String? {
        let numbers = numbers(of: places, shown: shown)
        guard places.count == numbers.count, !places.isEmpty else { return nil }
        let pairs = zip(places, numbers).map { "Chat-Platz \($0) = BILD \($1)" }.joined(separator: ", ")
        var text = "\n\nHINWEIS DES PROGRAMMS: Die Zahlwörter der Anfrage zählen die Bilder des ganzen "
            + "Chatverlaufs, nicht diese Auswahl. \(pairs)."
        if binding {
            text += " Setze als edit und reference ausschließlich diese BILD-Nummern."
        }
        return text + " Ignoriere jede andere Reihenfolge-Deutung."
    }

    private static func place(of slice: String) -> Int? {
        let folded = slice.lowercased()
        if let digits = folded.split(whereSeparator: { character in !character.isNumber })
            .first(where: { run in run.count <= 2 && run.allSatisfy(\.isNumber) }),
           let number = Int(String(digits)), number >= 1 {
            return number
        }
        var hit: (String, Int)?
        for entry in numberWords where folded.contains(entry.word) {
            if hit == nil || entry.word.count > hit!.0.count { hit = entry }
        }
        return hit?.1
    }
}
