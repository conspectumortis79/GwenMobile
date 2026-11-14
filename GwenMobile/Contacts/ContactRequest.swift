import GwenMobileKit
import Foundation

enum ContactRelation: String, CaseIterable, Sendable {
    case mother, father, parent
    case sister, brother, sibling
    case daughter, son, child
    case wife, husband, spouse, partner
    case grandmother, grandfather, grandparent
    case aunt, uncle, cousin
    case friend, assistant, manager

    static let noneValue = "none"

    static var toolValues: [String] { allCases.map(\.rawValue) + [noneValue] }

    init?(toolValue: String?) {
        guard let value = toolValue?.trimmed.lowercased(),
              let known = ContactRelation(rawValue: value) else { return nil }
        self = known
    }

    var narrower: Set<ContactRelation> {
        switch self {
        case .parent: return [.mother, .father]
        case .sibling: return [.sister, .brother]
        case .child: return [.daughter, .son]
        case .spouse: return [.wife, .husband, .partner]
        case .grandparent: return [.grandmother, .grandfather]
        default: return []
        }
    }

    func covers(_ other: ContactRelation) -> Bool {
        other == self || narrower.contains(other)
    }
}

enum PhoneKind: String, CaseIterable, Sendable {
    case mobile, main, home, work, other

    static let anyValue = "any"

    static var toolValues: [String] { [mobile, home, work, main].map(\.rawValue) + [anyValue] }

    static let preference: [PhoneKind] = [.mobile, .main, .home, .work, .other]

    init?(toolValue: String?) {
        guard let value = toolValue?.trimmed.lowercased(),
              value != PhoneKind.other.rawValue,
              let known = PhoneKind(rawValue: value) else { return nil }
        self = known
    }
}

struct ContactRequest: Equatable, Sendable {
    var person: String
    var group: String?
    var relation: ContactRelation?
    var numberKind: PhoneKind?

    var isEmpty: Bool {
        person.trimmed.isEmpty && relation == nil
    }

    var stepWords: String {
        StepWords.joined(person, group, relation?.rawValue, numberKind?.rawValue)
    }

    static func from(_ args: [String: Any]) -> ContactRequest? {
        let request = ContactRequest(person: ToolDecision.text(args, "person") ?? "",
                                  group: ToolDecision.text(args, "group"),
                                  relation: ContactRelation(toolValue: args["relation"] as? String),
                                  numberKind: PhoneKind(toolValue: args["number"] as? String))
        return request.isEmpty ? nil : request
    }
}
