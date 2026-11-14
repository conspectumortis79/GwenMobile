import GwenMobileKit
import Foundation

enum MusicAction: String, CaseIterable, Sendable {
    case play, pause, resume, next, previous
}

enum MusicKind: String, CaseIterable, Sendable {
    case song, artist, album, playlist, any
}

enum MusicService: String, CaseIterable, Codable, Sendable {
    case appleMusic = "apple_music"
    case spotify

    static let anyValue = "any"

    static var toolValues: [String] { allCases.map(\.rawValue) + [anyValue] }

    var label: String { self == .spotify ? "Spotify" : "Apple Music" }
}

struct MusicRequest: Equatable, Sendable {
    var action: MusicAction
    var query: String?
    var artist: String?
    var kind: MusicKind = .any
    var service: MusicService?

    var term: String {
        let asked = (query ?? "").trimmed
        return asked.isEmpty ? (artist ?? "").trimmed : asked
    }

    var wantsSomething: Bool { !term.isEmpty }

    var stepWords: String {
        StepWords.joined(action.rawValue, query, artist,
                         kind == .any ? nil : kind.rawValue, service?.rawValue)
    }

    static func from(_ args: [String: Any]) -> MusicRequest? {
        guard let action = MusicAction(rawValue: (ToolDecision.text(args, "action") ?? "").lowercased()) else {
            return nil
        }
        return MusicRequest(action: action, query: ToolDecision.text(args, "query"),
                            artist: ToolDecision.text(args, "artist"),
                            kind: MusicKind(rawValue: (ToolDecision.text(args, "kind") ?? "").lowercased()) ?? .any,
                            service: MusicService(rawValue: (ToolDecision.text(args, "service") ?? "").lowercased()))
    }
}
