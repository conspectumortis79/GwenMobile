import GwenMobileKit
import Foundation

enum ContactAnswer {
    static func who(_ target: CallTarget) -> String {
        target.label.isEmpty ? target.name : "\(target.name) · \(target.label)"
    }

    static func withRemark(_ line: String, _ note: GroupNote) -> String {
        guard let remark = remark(note) else { return line }
        return line + "\n" + remark
    }

    static func remark(_ note: GroupNote) -> String? {
        switch note {
        case .none: return nil
        case .missing(let group): return L.fmt("contact_group_missing", group)
        case .outside(let group): return L.fmt("contact_group_outside", group)
        }
    }

    static func lookupFailed(_ result: ContactLookupResult) -> String {
        switch result {
        case .denied: return L.t("contact_denied")
        case .unreadable: return L.t("contact_unreadable")
        case .resolved: return ""
        }
    }

    static func unsure(_ names: [String]) -> String { L.fmt("contact_unsure", names.joined(separator: ", ")) }

    static func notFound(_ request: ContactRequest) -> String { L.fmt("contact_not_found", asked(request)) }

    static func unresolved(_ resolution: ContactResolution, request: ContactRequest,
                           keyPrefix: String) -> String {
        switch resolution {
        case .ambiguous(let names): return L.fmt("\(keyPrefix)_ambiguous", names.joined(separator: ", "))
        case .unsure(let names): return unsure(names)
        case .noNumber(let name): return L.fmt("\(keyPrefix)_no_number", name)
        case .notFound, .unique: return notFound(request)
        }
    }

    static func asked(_ request: ContactRequest) -> String {
        let person = request.person.trimmed
        return person.isEmpty ? (request.relation?.rawValue ?? "") : person
    }
}
