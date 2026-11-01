import GwenMobileKit
#if !targetEnvironment(macCatalyst)
import Foundation

@MainActor
final class AppleMusicSource: MusicSource {
    private let library: any MusicLibraryReading
    private let catalog: any MusicCatalogSearching
    private let app: any MusicAppPlaying

    init(library: any MusicLibraryReading = MediaLibraryReader(),
         catalog: any MusicCatalogSearching = ITunesCatalogSearch(),
         app: any MusicAppPlaying = MusicAppPort.current) {
        self.library = library
        self.catalog = catalog
        self.app = app
    }

    var isPlaying: Bool { app.isPlaying }

    func play(_ request: MusicRequest) async -> MusicOutcome {
        guard await library.access() else { return .libraryDenied }
        guard request.wantsSomething else {
            app.perform(.resume)
            return .resumed
        }
        let entries = await library.entries(of: MusicLibraryMatching.kinds(for: request))
        if let entry = MusicLibraryMatching.best(for: request, in: entries) {
            return await app.play(entry) ? .playing(entry.pick) : .failed(L.fmt("music_start_refused", entry.name))
        }
        let found: CatalogPick?
        do {
            found = try await catalog.find(request)
        } catch {
            return .failed(TextLine.oneLine(error.localizedDescription, limit: 120))
        }
        guard let found else { return .notFound(request.term) }
        return await app.play(storeIDs: found.storeIDs) ? .playing(found.pick) : .catalogRefused(found.pick.name)
    }

    func control(_ action: MusicAction) async -> MusicOutcome {
        app.perform(action)
        return action == .resume || action == .play ? .resumed : .controlled(action)
    }
}

enum AppleMusicSourceFactory {
    @MainActor static func make() -> (any MusicSource)? { AppleMusicSource() }
}
#else
enum AppleMusicSourceFactory {
    @MainActor static func make() -> (any MusicSource)? { nil }
}
#endif
