import GwenMobileKit
import Foundation

struct CallTarget: Equatable, Sendable {
    let name: String
    let label: String
    let number: DialNumber
}

enum GroupNote: Equatable, Sendable {
    case none
    case missing(String)
    case outside(String)
}

enum ContactResolution: Equatable, Sendable {
    case unique(CallTarget, GroupNote)
    case ambiguous([String])
    case unsure([String])
    case noNumber(String)
    case notFound
}

enum ContactWords {
    static func words(_ text: String) -> [String] {
        SignalPhrase.words(in: text).map(\.folded)
    }

    static func allFound(_ wanted: [String], among present: [String], tolerant: Bool) -> Bool {
        !wanted.isEmpty && wanted.allSatisfy { word in
            present.contains { tolerant ? SignalPhrase.similar($0, word) : $0 == word }
        }
    }

    static func nameWords(of card: ContactCard) -> [String] {
        (card.nameParts + [card.name]).flatMap(words)
    }
}

struct GroupScope {
    let asked: String?
    let members: Set<String>?

    init(_ group: String?, cards: [ContactCard]) {
        let wanted = ContactWords.words(group ?? "")
        guard let group, !wanted.isEmpty else {
            asked = nil
            members = nil
            return
        }
        let inside = cards.filter { card in
            card.groups.contains { ContactWords.allFound(wanted, among: ContactWords.words($0), tolerant: false) }
        }
        asked = group
        members = inside.isEmpty ? nil : Set(inside.map(\.id))
    }

    func narrow(_ found: [ContactCard]) -> (cards: [ContactCard], note: GroupNote) {
        guard let asked else { return (found, .none) }
        guard let members else { return (found, .missing(asked)) }
        let inside = found.filter { members.contains($0.id) }
        if !inside.isEmpty { return (inside, .none) }
        return (found, found.isEmpty ? .none : .outside(asked))
    }
}

enum ContactMatching {
    static let listedLimit = 5

    static func resolve(_ request: ContactRequest, in cards: [ContactCard]) -> ContactResolution {
        let scope = GroupScope(request.group, cards: cards)
        let person = ContactWords.words(request.person)
        let related = relatedCards(request, person: person, in: cards)
        let named = cards.filter { ContactWords.allFound(person, among: ContactWords.nameWords(of: $0),
                                                         tolerant: false) }
        let (chosen, note) = scope.narrow(distinctCards(related.cards + named))
        guard !chosen.isEmpty else {
            if let unlinked = related.unlinked.first { return .noNumber(unlinked) }
            return guessed(person, kind: request.numberKind, scope: scope, in: cards)
        }
        let targets = distinctTargets(chosen.compactMap { target(for: $0, kind: request.numberKind) })
        switch targets.count {
        case 0: return .noNumber(chosen[0].name)
        case 1: return .unique(targets[0], note)
        default: return .ambiguous(listed(targets))
        }
    }

    static func target(for card: ContactCard, kind: PhoneKind?) -> CallTarget? {
        let order = kind.map { wanted in [wanted] + PhoneKind.preference.filter { $0 != wanted } }
            ?? PhoneKind.preference
        for wanted in order {
            for phone in card.phones where phone.kind == wanted {
                if let number = phone.dialable {
                    return CallTarget(name: card.name, label: phone.label, number: number)
                }
            }
        }
        return nil
    }

    private static func guessed(_ person: [String], kind: PhoneKind?, scope: GroupScope,
                                in cards: [ContactCard]) -> ContactResolution {
        let close = cards.filter { ContactWords.allFound(person, among: ContactWords.nameWords(of: $0),
                                                         tolerant: true) }
        let targets = distinctTargets(scope.narrow(close).cards.compactMap { target(for: $0, kind: kind) })
        return targets.isEmpty ? .notFound : .unsure(listed(targets))
    }

    private static func relatedCards(_ request: ContactRequest, person: [String],
                                     in cards: [ContactCard]) -> (cards: [ContactCard], unlinked: [String]) {
        var found: [ContactCard] = []
        var unlinked: [String] = []
        for card in cards {
            for tie in card.ties where names(tie, request: request, person: person) {
                let tieWords = ContactWords.words(tie.name)
                guard !tieWords.isEmpty else { continue }
                let linked = cards.filter {
                    $0.id != card.id
                        && ContactWords.allFound(tieWords, among: ContactWords.nameWords(of: $0), tolerant: false)
                }
                if linked.isEmpty { unlinked.append(tie.name) } else { found += linked }
            }
        }
        return (found, unlinked)
    }

    private static func names(_ tie: ContactTie, request: ContactRequest, person: [String]) -> Bool {
        if let wanted = request.relation, let own = tie.relation, wanted.covers(own) { return true }
        return ContactWords.allFound(person, among: ContactWords.words(tie.label), tolerant: false)
    }

    private static func distinctCards(_ cards: [ContactCard]) -> [ContactCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    private static func distinctTargets(_ targets: [CallTarget]) -> [CallTarget] {
        var seen = Set<DialNumber>()
        return targets.filter { seen.insert($0.number).inserted }
    }

    private static func listed(_ targets: [CallTarget]) -> [String] {
        let names = targets.map(\.name)
        return Array(targets.map { target in
            names.filter { $0 == target.name }.count > 1 ? "\(target.name) · \(target.label)" : target.name
        }.prefix(listedLimit))
    }
}
