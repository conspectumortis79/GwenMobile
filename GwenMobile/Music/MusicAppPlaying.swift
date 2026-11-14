import GwenMobileKit
import Foundation

@MainActor
protocol MusicAppPlaying {
    var isPlaying: Bool { get }
    func play(_ entry: MusicLibraryEntry) async -> Bool
    func play(storeIDs: [String]) async -> Bool
    func perform(_ action: MusicAction)
}
