import GwenMobileKit
import Foundation

@MainActor
struct PictureSearchFlow {
    private let search: any PictureSearching
    private let fetch: any RemoteImageFetching
    private let media: any GalleryStoring
    private let onStatus: (String) -> Void

    init(search: any PictureSearching = BingPictureSearch(),
         fetch: any RemoteImageFetching = HTTPPictureFetching(),
         media: any GalleryStoring,
         onStatus: @escaping (String) -> Void = { _ in }) {
        self.search = search
        self.fetch = fetch
        self.media = media
        self.onStatus = onStatus
    }

    func run(query: String, offset: Int = 1) async throws -> PictureRound {
        let searcher = search
        let hits = try await Offload.run { try await searcher.pictures(for: query, offset: offset) }
        let wanted = Array(hits.prefix(ImagePolicy.galleryMaxStored))
        guard !wanted.isEmpty else { throw APIError(message: L.t("pictures_none_found")) }
        onStatus(L.t("pictures_loading"))
        let downloaded = await download(wanted)
        let media = self.media
        let pictures: [WebPicture] = try await Offload.run {
            Self.store(downloaded, over: wanted, media: media)
        }
        guard !pictures.isEmpty else { throw APIError(message: L.t("pictures_load_failed")) }
        let next = offset.addingReportingOverflow(wanted.count)
        return PictureRound(pictures: pictures,
                            nextOffset: next.overflow ? Int.max : next.partialValue,
                            exhausted: hits.count <= wanted.count,
                            failures: wanted.count - pictures.count)
    }

    nonisolated static func store(_ downloaded: [(Int, Data)], over hits: [PictureHit],
                                  media: any GalleryStoring) -> [WebPicture] {
        var stored: [WebPicture] = []
        for (index, bytes) in downloaded.sorted(by: { $0.0 < $1.0 }) {
            guard hits.indices.contains(index), let file = media.storeGalleryPicture(bytes) else { continue }
            let hit = hits[index]
            stored.append(WebPicture(file: file, pageURL: hit.pageURL, fullURL: hit.fullURL,
                                     title: hit.title, domain: hit.domain))
        }
        return stored
    }

    private func download(_ hits: [PictureHit]) async -> [(Int, Data)] {
        let fetch = self.fetch
        let grab: @Sendable (Int) async -> (Int, Data)? = { index in
            guard let url = HTTPPictureFetching.secureURL(hits[index].thumbURL),
                  let bytes = try? await fetch.data(from: url) else { return nil }
            return (index, bytes)
        }
        var done: [(Int, Data)] = []
        await withTaskGroup(of: (Int, Data)?.self) { group in
            var launched = 0
            let window = ImagePolicy.galleryDownloadWindow
            func launchNext() {
                let index = launched
                launched += 1
                group.addTask { await grab(index) }
            }
            while launched < min(hits.count, window) {
                launchNext()
            }
            for await result in group {
                if let result { done.append(result) }
                guard launched < hits.count else { continue }
                launchNext()
            }
        }
        return done
    }
}
