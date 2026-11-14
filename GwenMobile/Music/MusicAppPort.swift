import GwenMobileKit
import Foundation

@MainActor
struct StubMusicApp: MusicAppPlaying {
    var isPlaying: Bool { false }
    func play(_ entry: MusicLibraryEntry) async -> Bool { false }
    func play(storeIDs: [String]) async -> Bool { false }
    func perform(_ action: MusicAction) {}
}

@MainActor
enum MusicAppPort {
    nonisolated(unsafe) static var current: any MusicAppPlaying = StubMusicApp()
}
