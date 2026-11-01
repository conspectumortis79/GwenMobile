@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

enum StepClass: String {
    case answer, gallery, picture, calendar, reminder, timer, readAloud, readAnswer, place, price, priceWatch, briefing, code, translate, call, clock, music, message, memory, history, weather, scan

    init(_ kind: SendStepKind) {
        switch kind {
        case .chat, .search, .status: self = .answer
        case .gallery: self = .gallery
        case .create, .edit: self = .picture
        case .video: self = .answer
        case .calendar: self = .calendar
        case .reminder: self = .reminder
        case .timer: self = .timer
        case .readAloud: self = .readAloud
        case .readAnswer: self = .readAnswer
        case .place, .route: self = .place
        case .price: self = .price
        case .priceWatch: self = .priceWatch
        case .briefing: self = .briefing
        case .code: self = .code
        case .translate: self = .translate
        case .call: self = .call
        case .clock: self = .clock
        case .music: self = .music
        case .message: self = .message
        case .memory: self = .memory
        case .history: self = .history
        case .weather: self = .weather
        case .scan: self = .scan
        }
    }
}

struct AppointmentSlot: Equatable {
    let dayOffset: Int
    let hour: Int
    var minute = 0

    var label: String { "+\(dayOffset)t_\(hour):" + String(format: "%02d", minute) }

    func date(after now: Date, in calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

struct PictureLook: Equatable {
    let chroma: Double
    let description: String

    static let colourThreshold = 20.0

    var isColour: Bool { chroma >= Self.colourThreshold }
    var isGradable: Bool { !description.hasPrefix(VisionPictureDescriber.failureMark) }
}

struct WishOutcome {
    let steps: [ToolDecision]
    let answers: [ChatMessage]
    let looks: [PictureLook]
    let liveStarts: [Date?]
    let now: Date

    var refs: [CalendarRef] { answers.compactMap(\.calendarRef) }
    var pictureFiles: [String] { answers.flatMap { ($0.outImages ?? []).map(\.file) } }
    var foldedText: String { TextFolding.fold(answers.map(\.text).joined(separator: "\n")) }
    var stepTrace: String { steps.map { StepClass($0.stepKind).rawValue }.joined(separator: ">") }
}

enum WishExpectation {
    case steps([StepClass])
    case pictures(Int)
    case appointments([AppointmentSlot])
    case picture(Int, shows: [String], colour: Bool?)
    case gallery(about: [String])
    case places(named: String)
    case placeBlock(heading: String, named: String)
    case text(all: [String], any: [String] = [], none: [String] = [])
    case noWarning

    var name: String {
        switch self {
        case .steps(let wanted): return "schritte_" + wanted.map(\.rawValue).joined(separator: ">")
        case .pictures(let count): return "genau_\(count)_bilder"
        case .appointments(let slots): return "termine_" + slots.map(\.label).joined(separator: ",")
        case .picture(let index, let shows, let colour):
            return "bild\(index + 1)_" + shows.joined(separator: "|")
                + (colour.map { $0 ? "_farbig" : "_schwarzweiss" } ?? "")
        case .gallery(let about): return "galerie_" + about.joined(separator: "_")
        case .places(let word): return "orte_" + word
        case .placeBlock(let heading, let word): return "block_\(heading)_" + word
        case .text(let all, let any, let none):
            return "text_" + (all + any.map { "~" + $0 } + none.map { "!" + $0 }).joined(separator: ",")
        case .noWarning: return "keine_warnung"
        }
    }

    func met(_ outcome: WishOutcome) -> Bool {
        switch self {
        case .steps(let wanted):
            return outcome.steps.map { StepClass($0.stepKind) } == wanted
        case .pictures(let count):
            return outcome.pictureFiles.count == count
        case .appointments(let slots):
            return Self.appointmentsMatch(slots, outcome: outcome)
        case .picture(let index, let shows, let colour):
            guard outcome.looks.indices.contains(index) else { return false }
            let look = outcome.looks[index]
            let seen = TextFolding.fold(look.description)
            let motif = shows.contains { seen.contains(TextFolding.fold($0)) }
            return motif && (colour.map { $0 == look.isColour } ?? true)
        case .gallery(let about):
            return outcome.answers.contains { answer in
                guard let gallery = answer.gallery, !gallery.pictures.isEmpty else { return false }
                let query = TextFolding.fold(gallery.query)
                return about.allSatisfy { query.contains(TextFolding.fold($0)) }
            }
        case .places(let word):
            let wanted = TextFolding.fold(word)
            return outcome.answers.contains { answer in
                guard let first = answer.allPlaces.first else { return false }
                return TextFolding.fold(first.name).contains(wanted)
            }
        case .placeBlock(let heading, let word):
            let wanted = TextFolding.fold(word)
            return outcome.answers.contains { answer in
                (answer.placeGroups ?? []).contains { group in
                    group.headingKey == heading
                        && (group.places.first.map { TextFolding.fold($0.name).contains(wanted) } ?? false)
                }
            }
        case .text(let all, let any, let none):
            let text = outcome.foldedText
            let has = { (word: String) in text.contains(TextFolding.fold(word)) }
            return all.allSatisfy(has) && (any.isEmpty || any.contains(where: has)) && !none.contains(where: has)
        case .noWarning:
            return !outcome.answers.contains { $0.text.contains("\u{26a0}\u{fe0f}") }
        }
    }

    private static func appointmentsMatch(_ slots: [AppointmentSlot], outcome: WishOutcome) -> Bool {
        let refs = outcome.refs
        guard refs.count == slots.count, outcome.liveStarts.count == refs.count else { return false }
        for (index, slot) in slots.enumerated() {
            guard let wanted = slot.date(after: outcome.now),
                  let live = outcome.liveStarts[index] else { return false }
            guard refs[index].start == wanted, live == wanted else { return false }
        }
        return true
    }
}
#endif
