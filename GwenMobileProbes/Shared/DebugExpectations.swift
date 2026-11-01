@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
struct TurnArtifacts {
    var answers = 0
    var text = 0
    var pictures = 0
    var gallery = 0
    var places = 0
    var sources = 0
    var price = false
    var priceRounds = 0
    var appointments = 0
    var fullText = ""
    var texts: [String] = []
    var titles: [String] = []
    var refs: [CalendarRef] = []

    mutating func take(_ answer: ChatMessage) {
        let body = answer.text.trimmed
        answers += 1
        text = max(text, body.count)
        fullText += "\n" + body
        texts.append(body)
        pictures += answer.outImages?.count ?? 0
        gallery += answer.hasGallery ? (answer.gallery?.pictures.count ?? 0) : 0
        places += answer.allPlaces.count
        sources += answer.sources?.count ?? 0
        price = price || answer.sourcesHeadingKey == "price_head"
        if answer.sourcesHeadingKey == "price_head" { priceRounds += 1 }
        if let ref = answer.calendarRef {
            appointments += 1
            titles.append(ref.title)
            refs.append(ref)
        }
    }
}

enum TurnExpectation {
    case text
    case picture
    case exactly(Int)
    case bubbles(Int)
    case noGallery
    case gallery
    case places
    case price
    case priceRounds(Int)
    case appointment
    case appointments(Int)
    case noWarning
    case sources
    case all(label: String, list: [String])
    case once(label: String, word: String)
    case any(label: String, list: [String])
    case titleContains(String)
    case lastStart(hour: Int)
    case bubbleMentions(Int, String)

    var name: String {
        switch self {
        case .text: return "text"
        case .picture: return "bild"
        case .exactly(let want): return "genau_\(want)_bilder"
        case .bubbles(let want): return "genau_\(want)_blasen"
        case .noGallery: return "keine_galerie"
        case .gallery: return "galerie"
        case .places: return "orte"
        case .price: return "preise"
        case .priceRounds(let want): return "preisrunden_\(want)"
        case .appointment: return "termin"
        case .appointments(let want): return "termine_\(want)"
        case .noWarning: return "keine_warnung"
        case .sources: return "quellen"
        case .all(let label, _), .any(let label, _): return "wort_\(label)"
        case .once(let label, _): return "genau_einmal_\(label)"
        case .titleContains(let want): return "titel_\(want)"
        case .lastStart(let hour): return "letzter_termin_um_\(hour)_uhr"
        case .bubbleMentions(let index, let word): return "blase\(index + 1)_nennt_\(word)"
        }
    }

    func met(_ a: TurnArtifacts) -> Bool {
        let lower = a.fullText.lowercased()
        switch self {
        case .text: return a.text > 120
        case .picture: return a.pictures >= 1
        case .exactly(let want): return a.pictures == want
        case .bubbles(let want): return a.answers == want
        case .noGallery: return a.gallery == 0
        case .gallery: return a.gallery > 0
        case .places: return a.places > 0
        case .price: return a.price
        case .priceRounds(let want): return a.priceRounds == want
        case .appointment: return a.appointments >= 1
        case .appointments(let want): return a.appointments == want
        case .noWarning: return !a.fullText.contains("\u{26a0}\u{fe0f}")
        case .sources: return a.sources > 0
        case .all(_, let list): return list.allSatisfy { lower.contains($0.lowercased()) }
        case .once(_, let word): return a.fullText.lowercased().components(separatedBy: word.lowercased()).count - 1 == 1
        case .any(_, let list): return list.contains { lower.contains($0.lowercased()) }
        case .titleContains(let want): return a.titles.contains { $0.localizedCaseInsensitiveContains(want) }
        case .bubbleMentions(let index, let word):
            return a.texts.indices.contains(index) && a.texts[index].lowercased().contains(word.lowercased())
        case .lastStart(let hour):
            return a.refs.last.map { Calendar.current.component(.hour, from: $0.start) == hour } ?? false
        }
    }
}
#endif
