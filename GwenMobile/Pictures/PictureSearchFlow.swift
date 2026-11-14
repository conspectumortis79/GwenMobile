import GwenMobileKit
import Foundation

@MainActor
struct PictureSearchFlow {
    private let search: any PictureSearching
    private let fetch: any RemoteImageFetching
    private let media: any GalleryStoring
    private let gate: SourceGate
    private let onStatus: (String) -> Void

    init(search: any PictureSearching = BingPictureSearch(),
         fetch: any RemoteImageFetching = HTTPPictureFetching(),
         media: any GalleryStoring,
         gate: SourceGate = .local,
         onStatus: @escaping (String) -> Void = { _ in }) {
        self.search = search
        self.fetch = fetch
        self.media = media
        self.gate = gate
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
            Self.store(downloaded.pictures, over: wanted, media: media)
        }
        let report = WebSourceReport(used: pictures.count, issues: downloaded.issues)
        guard !pictures.isEmpty || report.blockedCount > 0 else {
            throw APIError(message: L.t("pictures_load_failed"))
        }
        flowMark("BILDQUELLEN quellen=\(pictures.count) "
                 + "nicht_verwendet=\(report.sourceIssues.count) blockiert=\(report.blockedCount)")
        let next = offset.addingReportingOverflow(wanted.count)
        return PictureRound(pictures: pictures,
                            nextOffset: next.overflow ? Int.max : next.partialValue,
                            exhausted: hits.count <= wanted.count,
                            failures: wanted.count - pictures.count,
                            report: report)
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

    private enum FetchOutcome: Sendable {
        case stored(Int, Data)
        case failed(WebSourceIssue)
    }

    private func download(_ hits: [PictureHit]) async
        -> (pictures: [(Int, Data)], issues: [WebSourceIssue]) {
        let fetch = self.fetch
        let gate = self.gate
        var blockedIssues: [Int: WebSourceIssue] = [:]
        for (index, hit) in hits.enumerated() {
            guard let page = URL(string: hit.pageURL), gate.isBlocked(page) else { continue }
            blockedIssues[index] = WebSourceIssue(kind: .blocked, domain: hit.domain,
                                                  reason: L.t("source_report_blocked_reason"))
        }
        let blocked = blockedIssues
        let grab: @Sendable (Int) async -> FetchOutcome = { index in
            if let issue = blocked[index] { return .failed(issue) }
            guard let url = HTTPPictureFetching.secureURL(hits[index].thumbURL) else {
                return .failed(WebSourceIssue(kind: .unavailable, domain: hits[index].domain,
                                              reason: L.t("pictures_insecure")))
            }
            do {
                return .stored(index, try await fetch.data(from: url))
            } catch {
                let message = (error as? APIError)?.message ?? error.localizedDescription
                let kind: WebSourceIssue.Kind = message.contains("HTTP 403") ? .blocked : .unavailable
                return .failed(WebSourceIssue(kind: kind, domain: hits[index].domain, reason: message))
            }
        }
        var pictures: [(Int, Data)] = []
        var issues: [WebSourceIssue] = []
        await withTaskGroup(of: FetchOutcome.self) { group in
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
            for await outcome in group {
                switch outcome {
                case .stored(let index, let data): pictures.append((index, data))
                case .failed(let issue): issues.append(issue)
                }
                guard launched < hits.count else { continue }
                launchNext()
            }
        }
        issues = Self.unique(issues)
        issues.sort {
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            return $0.reason < $1.reason
        }
        return (pictures, issues)
    }

    private static func unique(_ issues: [WebSourceIssue]) -> [WebSourceIssue] {
        var seen = Set<WebSourceIssue>()
        return issues.filter { seen.insert($0).inserted }
    }
}
