import GwenMobileKit
import Foundation

protocol PictureSearching: Sendable {
    func pictures(for query: String, offset: Int) async throws -> [PictureHit]
}

struct BingPictureSearch: PictureSearching {
    static let endpoint = "https://www.bing.com/images/async"
    static let thumbnailPath = "/th"
    static let photoFilter = "+filterui:photo-photo"
    static let resultPattern = "[ >]m=\"([^\"]+)\""

    static func request(query: String, offset: Int, endpoint: String = endpoint) throws -> URLRequest {
        guard let trimmed = query.trimmed.nilIfEmpty else {
            throw APIError(message: L.t("web_bad_query"))
        }
        guard var components = URLComponents(string: endpoint) else {
            throw APIError(message: L.t("web_bad_query"))
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "first", value: String(max(1, offset))),
            URLQueryItem(name: "count", value: String(ImagePolicy.galleryPageSpan)),
            URLQueryItem(name: "mmasync", value: "1"),
            URLQueryItem(name: "qft", value: photoFilter),
            URLQueryItem(name: "safeSearch", value: "strict"),
        ]
        guard let url = components.url else { throw APIError(message: L.t("web_bad_query")) }
        return WebSearch.pageRequest(url, accept: "text/html,application/xhtml+xml")
    }

    static func hits(from html: String) -> [PictureHit] {
        guard let regex = try? NSRegularExpression(pattern: resultPattern) else { return [] }
        let text = html as NSString
        var found: [PictureHit] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            guard match.numberOfRanges > 1,
                  let hit = hit(fromJSON: HTMLEntities.decoded(text.substring(with: match.range(at: 1))))
            else { continue }
            guard seen.insert(hit.thumbURL).inserted else { continue }
            found.append(hit)
        }
        return found
    }

    static func hit(fromJSON json: String) -> PictureHit? {
        guard let data = json.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let turl = args["turl"] as? String,
              let thumb = thumbnailURL(from: turl) else { return nil }
        let page = (args["purl"] as? String) ?? (args["murl"] as? String) ?? ""
        guard let pageURL = URL(string: page), let scheme = pageURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http", pageURL.host != nil else { return nil }
        let full = (args["murl"] as? String) ?? page
        let fullScheme = URL(string: full)?.scheme?.lowercased()
        let fullURL = fullScheme == "http" || fullScheme == "https" ? full : page
        return PictureHit(thumbURL: thumb,
                          pageURL: pageURL.absoluteString,
                          fullURL: fullURL,
                          title: cleanedTitle(args["t"] as? String, pageURL),
                          domain: WebSearch.domain(of: pageURL))
    }

    static func thumbnailURL(from turl: String) -> String? {
        guard let source = URLComponents(string: turl),
              source.scheme == "https", let host = source.host,
              let id = source.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty
        else { return nil }
        var rebuilt = URLComponents()
        rebuilt.scheme = "https"
        rebuilt.host = host
        rebuilt.path = source.path.isEmpty ? thumbnailPath : source.path
        rebuilt.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "w", value: String(ImagePolicy.galleryThumbPixel)),
        ]
        return rebuilt.url?.absoluteString
    }

    private static func cleanedTitle(_ raw: String?, _ pageURL: URL) -> String {
        let title = (raw ?? "").trimmed
        return title.isEmpty ? WebSearch.domain(of: pageURL) : String(title.prefix(160))
    }

    func pictures(for query: String, offset: Int) async throws -> [PictureHit] {
        let (data, response) = try await HTTP.data(Self.request(query: query, offset: offset))
        try HTTP.ensureSuccess(response)
        let html = String(decoding: data, as: UTF8.self)
        let found = Self.hits(from: html)
        guard !found.isEmpty else { throw APIError(message: L.t("pictures_none_found")) }
        return found
    }
}
