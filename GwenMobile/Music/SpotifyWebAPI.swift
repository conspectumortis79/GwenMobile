import GwenMobileKit
import Foundation

struct SpotifyTarget: Equatable, Sendable {
    let uri: String
    let pick: MusicPick

    var isTrack: Bool { uri.hasPrefix("spotify:track:") }
}

enum SpotifyWebAPI {
    static let host = "https://api.spotify.com/v1"
    static let searchLimit = 10
    static let playlistLimit = 50
    static let timeout: TimeInterval = 15

    static func searchType(for kind: MusicKind) -> String {
        switch kind {
        case .artist: return "artist"
        case .album: return "album"
        case .playlist: return "playlist"
        case .song, .any: return "track"
        }
    }

    static func searchQuery(for request: MusicRequest) -> String {
        guard request.query != nil, let artist = request.artist, !artist.isEmpty, request.kind != .artist else {
            return request.term
        }
        return "\(request.term) artist:\(artist)"
    }

    static func search(_ request: MusicRequest, token: String) -> URLRequest? {
        var components = URLComponents(string: host + "/search")
        components?.queryItems = [URLQueryItem(name: "q", value: searchQuery(for: request)),
                                  URLQueryItem(name: "type", value: searchType(for: request.kind)),
                                  URLQueryItem(name: "limit", value: String(searchLimit))]
        return components?.url.map { authorized(URLRequest(url: $0), token: token) }
    }

    static func myPlaylists(token: String) -> URLRequest? {
        URL(string: host + "/me/playlists?limit=\(playlistLimit)").map { authorized(URLRequest(url: $0), token: token) }
    }

    static func play(_ target: SpotifyTarget?, token: String) -> URLRequest? {
        guard var request = URL(string: host + "/me/player/play").map({ URLRequest(url: $0) }) else { return nil }
        request.httpMethod = "PUT"
        if let target {
            let body: [String: Any] = target.isTrack ? ["uris": [target.uri]] : ["context_uri": target.uri]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return authorized(request, token: token)
    }

    static func control(_ action: MusicAction, token: String) -> URLRequest? {
        let (path, method): (String, String)
        switch action {
        case .pause: (path, method) = ("/me/player/pause", "PUT")
        case .next: (path, method) = ("/me/player/next", "POST")
        case .previous: (path, method) = ("/me/player/previous", "POST")
        case .play, .resume: return play(nil, token: token)
        }
        guard var request = URL(string: host + path).map({ URLRequest(url: $0) }) else { return nil }
        request.httpMethod = method
        return authorized(request, token: token)
    }

    static func authorized(_ request: URLRequest, token: String) -> URLRequest {
        var request = request
        request.timeoutInterval = timeout
        HTTP.authorize(&request, key: token)
        return request
    }

    static func targets(from data: Data, kind: MusicKind) -> [SpotifyTarget] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let type = searchType(for: kind)
        let items = (object[type + "s"] as? [String: Any])?["items"] as? [Any] ?? object["items"] as? [Any] ?? []
        return items.compactMap { $0 as? [String: Any] }.compactMap { item in
            guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
            let artist = ((item["artists"] as? [[String: Any]])?.first?["name"] as? String)
            return SpotifyTarget(uri: uri, pick: MusicPick(kind: kind == .any ? .song : kind, name: name,
                                                           artist: artist))
        }
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func bestPlaylist(_ wanted: String, in playlists: [SpotifyTarget]) -> SpotifyTarget? {
        let words = ContactWords.words(wanted)
        guard !words.isEmpty else { return nil }
        return playlists.first { ContactWords.words($0.pick.name) == words }
            ?? playlists.first { ContactWords.allFound(words, among: ContactWords.words($0.pick.name), tolerant: false) }
    }
}

enum SpotifyWebResult: Equatable, Sendable {
    case done
    case refused(String)
}

protocol SpotifyWebControlling: Sendable {
    func find(_ request: MusicRequest, token: String) async throws -> SpotifyTarget?
    func play(_ target: SpotifyTarget?, token: String) async throws -> SpotifyWebResult
    func perform(_ action: MusicAction, token: String) async throws -> SpotifyWebResult
}

struct SpotifyWebClient: SpotifyWebControlling {
    let send: @Sendable (URLRequest) async throws -> (Data, Int)

    init() {
        self.init(send: SpotifyWebClient.transport)
    }

    init(send: @escaping @Sendable (URLRequest) async throws -> (Data, Int)) {
        self.send = send
    }

    static func transport(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await HTTP.data(request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    func find(_ request: MusicRequest, token: String) async throws -> SpotifyTarget? {
        if request.kind == .playlist, let mine = SpotifyWebAPI.myPlaylists(token: token) {
            let (data, status) = try await send(mine)
            if (200..<300).contains(status),
               let own = SpotifyWebAPI.bestPlaylist(request.term, in: SpotifyWebAPI.targets(from: data, kind: .playlist)) {
                return own
            }
        }
        guard let search = SpotifyWebAPI.search(request, token: token) else { return nil }
        let (data, status) = try await send(search)
        guard (200..<300).contains(status) else {
            throw APIError(message: SpotifyWebAPI.errorMessage(from: data) ?? "HTTP \(status)", status: status)
        }
        return SpotifyWebAPI.targets(from: data, kind: request.kind).first
    }

    func play(_ target: SpotifyTarget?, token: String) async throws -> SpotifyWebResult {
        guard let request = SpotifyWebAPI.play(target, token: token) else { return .refused("url") }
        return try await result(of: request)
    }

    func perform(_ action: MusicAction, token: String) async throws -> SpotifyWebResult {
        guard let request = SpotifyWebAPI.control(action, token: token) else { return .refused("url") }
        return try await result(of: request)
    }

    private func result(of request: URLRequest) async throws -> SpotifyWebResult {
        let (data, status) = try await send(request)
        if (200..<300).contains(status) { return .done }
        return .refused(SpotifyWebAPI.errorMessage(from: data) ?? "HTTP \(status)")
    }
}
