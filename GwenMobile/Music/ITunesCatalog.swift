import GwenMobileKit
import Foundation

struct ITunesItem: Equatable, Sendable {
    let trackID: Int?
    let collectionID: Int?
    let name: String
    let artist: String
    let trackNumber: Int?
}

struct CatalogPick: Equatable, Sendable {
    let storeIDs: [String]
    let pick: MusicPick
}

protocol MusicCatalogSearching: Sendable {
    func find(_ request: MusicRequest) async throws -> CatalogPick?
}

enum ITunesCatalog {
    static let host = "https://itunes.apple.com"
    static let songLimit = 10
    static let artistLimit = 25

    static func country(_ locale: Locale = .current) -> String {
        (locale.region?.identifier ?? "US").lowercased()
    }

    static func searchURL(term: String, entity: String, attribute: String? = nil, limit: Int,
                          country: String) -> URL? {
        var components = URLComponents(string: host + "/search")
        var items = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "media", value: "music"),
                     URLQueryItem(name: "entity", value: entity), URLQueryItem(name: "limit", value: String(limit)),
                     URLQueryItem(name: "country", value: country)]
        if let attribute { items.append(URLQueryItem(name: "attribute", value: attribute)) }
        components?.queryItems = items
        return components?.url
    }

    static func lookupURL(collectionID: Int, country: String) -> URL? {
        var components = URLComponents(string: host + "/lookup")
        components?.queryItems = [URLQueryItem(name: "id", value: String(collectionID)),
                                  URLQueryItem(name: "entity", value: "song"),
                                  URLQueryItem(name: "country", value: country)]
        return components?.url
    }

    static func items(from data: Data) -> [ITunesItem] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { entry in
            let wrapper = entry["wrapperType"] as? String
            let name = (wrapper == "collection" ? entry["collectionName"] : entry["trackName"]) as? String
            guard let name, wrapper == "track" || wrapper == "collection" else { return nil }
            return ITunesItem(trackID: wrapper == "track" ? entry["trackId"] as? Int : nil,
                              collectionID: entry["collectionId"] as? Int, name: name,
                              artist: entry["artistName"] as? String ?? "",
                              trackNumber: entry["trackNumber"] as? Int)
        }
    }

    static func artistFits(_ item: ITunesItem, _ wanted: String) -> Bool {
        let words = ContactWords.words(wanted)
        return words.isEmpty || ContactWords.allFound(words, among: ContactWords.words(item.artist), tolerant: false)
    }
}

struct ITunesCatalogSearch: MusicCatalogSearching {
    let country: String
    let fetch: @Sendable (URL) async throws -> Data

    init() {
        self.init(country: ITunesCatalog.country())
    }

    init(country: String) {
        self.init(country: country, fetch: ITunesCatalogSearch.download)
    }

    init(country: String, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.country = country
        self.fetch = fetch
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        return try await HTTP.jsonData(request)
    }

    func find(_ request: MusicRequest) async throws -> CatalogPick? {
        switch request.kind {
        case .artist: return try await artist(request)
        case .album: return try await album(request)
        case .playlist: return nil
        case .song, .any: return try await song(request)
        }
    }

    private func song(_ request: MusicRequest) async throws -> CatalogPick? {
        let term = [request.term, request.query == nil ? "" : request.artist ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard let url = ITunesCatalog.searchURL(term: term, entity: "song", limit: ITunesCatalog.songLimit,
                                                country: country) else { return nil }
        let found = ITunesCatalog.items(from: try await fetch(url)).filter { $0.trackID != nil }
        let artist = request.query == nil ? "" : request.artist ?? ""
        guard let hit = found.first(where: { ITunesCatalog.artistFits($0, artist) }) ?? found.first,
              let id = hit.trackID else { return nil }
        return CatalogPick(storeIDs: [String(id)],
                           pick: MusicPick(kind: .song, name: hit.name, artist: hit.artist))
    }

    private func artist(_ request: MusicRequest) async throws -> CatalogPick? {
        guard let url = ITunesCatalog.searchURL(term: request.term, entity: "song", attribute: "artistTerm",
                                                limit: ITunesCatalog.artistLimit, country: country) else { return nil }
        let found = ITunesCatalog.items(from: try await fetch(url))
            .filter { $0.trackID != nil && ITunesCatalog.artistFits($0, request.term) }
        guard let first = found.first else { return nil }
        return CatalogPick(storeIDs: found.compactMap { $0.trackID }.map(String.init),
                           pick: MusicPick(kind: .artist, name: first.artist))
    }

    private func album(_ request: MusicRequest) async throws -> CatalogPick? {
        let term = [request.term, request.query == nil ? "" : request.artist ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard let url = ITunesCatalog.searchURL(term: term, entity: "album", limit: 5,
                                               country: country) else { return nil }
        let albums = ITunesCatalog.items(from: try await fetch(url)).filter { $0.collectionID != nil }
        let artist = request.query == nil ? "" : request.artist ?? ""
        guard let album = albums.first(where: { ITunesCatalog.artistFits($0, artist) }) ?? albums.first,
              let collection = album.collectionID,
              let lookup = ITunesCatalog.lookupURL(collectionID: collection, country: country) else { return nil }
        let tracks = ITunesCatalog.items(from: try await fetch(lookup))
            .filter { $0.trackID != nil }
            .sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
        guard !tracks.isEmpty else { return nil }
        return CatalogPick(storeIDs: tracks.compactMap { $0.trackID }.map(String.init),
                           pick: MusicPick(kind: .album, name: album.name, artist: album.artist))
    }
}
