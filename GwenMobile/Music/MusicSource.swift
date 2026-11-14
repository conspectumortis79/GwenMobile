import GwenMobileKit

struct MusicPick: Equatable, Sendable {
    let kind: MusicKind
    let name: String
    var artist: String?
}

enum MusicOutcome: Equatable, Sendable {
    case playing(MusicPick)
    case resumed
    case controlled(MusicAction)
    case openedApp(MusicPick?)
    case notFound(String)
    case catalogRefused(String)
    case libraryDenied
    case notSetUp
    case notConnected
    case unsupported
    case failed(String)

    var soundsNow: Bool {
        switch self {
        case .playing, .resumed, .controlled, .openedApp: return true
        default: return false
        }
    }
}

@MainActor
protocol MusicSource {
    var isPlaying: Bool { get }
    func play(_ request: MusicRequest) async -> MusicOutcome
    func control(_ action: MusicAction) async -> MusicOutcome
}
