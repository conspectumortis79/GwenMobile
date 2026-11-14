import GwenMobileKit
import Foundation

enum ScanKind: String, Codable, Equatable, Sendable, CaseIterable {
    case invoice
    case authority
    case receipt
    case letter
    case other

    static let toolValues = allCases.map(\.rawValue)

    static func named(_ raw: String?) -> ScanKind {
        let cleaned = raw?.trimmed.lowercased() ?? ""
        return ScanKind(rawValue: cleaned) ?? .other
    }

    var fileNameKey: String { "scan_file_\(rawValue)" }
    var taskKey: String { "scan_task_\(rawValue)" }
}

struct ScanRequest: Equatable, Sendable {
    var kind: ScanKind
    var remind: Bool

    static func from(_ args: [String: Any]) -> ScanRequest {
        ScanRequest(kind: ScanKind.named(args["kind"] as? String),
                    remind: args["remind"] as? Bool ?? false)
    }

    var stepWords: String {
        kind.rawValue + (remind ? " erinnerung" : "")
    }
}
