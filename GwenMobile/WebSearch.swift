import Foundation

struct WebHit: Sendable {
    var title: String
    var url: String
    var domain: String
    var text: String

    func sourceBlock(numbered number: Int) -> String {
        "## Quelle [\(number)] \(title) — \(domain)\n\(text)\n\n"
    }
}

enum WebSearch {
    static let searchUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let scanLimit = 8
    static let resultLimit = 3
    static let minimumResultCount = 1
    static let maxTextChars = 4000
    static let minTextChars = 200
    static let blockedDomains: Set<String> = [
        "duckduckgo.com", "google.com", "bing.com", "youtube.com", "youtu.be",
        "facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com",
        "pinterest.com", "reddit.com", "amazon.de", "amazon.com", "ebay.de",
        "tripadvisor.com", "gamepedia.com", "fandom.com", "wikihow.com",
    ]

    static func domain(of url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst("www.".count)) : host
    }

    static func search(_ query: String) async throws -> [URL] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(enc)") else {
            throw APIError(message: L.t("web_bad_query"))
        }
        var req = URLRequest(url: url)
        req.setValue(searchUA, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = APITimeout.webPageRequest
        let (data, resp) = try await HTTP.data(req, using: URLSession.shared)
        try HTTP.ensureSuccess(resp)
        guard let html = String(data: data, encoding: .utf8) else {
            throw APIError(message: L.t("web_no_results"))
        }
        var results: [URL] = []
        var seenDomains = Set<String>()
        let pattern = "result__a[^>]*href=\"([^\"]+)\"[^>]*>(?:[^<]{4,160})"
        guard let re = try? NSRegularExpression(pattern: pattern) else { throw APIError(message: L.t("web_no_results")) }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = resolvedHref(ns.substring(with: m.range(at: 1)))
            guard let u = URL(string: href), u.scheme?.hasPrefix("http") == true else { continue }
            let dom = domain(of: u)
            let root = dom.split(separator: ".").suffix(2).joined(separator: ".")
            guard !blockedDomains.contains(dom), !blockedDomains.contains(root),
                  !seenDomains.contains(root) else { continue }
            seenDomains.insert(root)
            results.append(u)
            if results.count >= scanLimit { break }
        }
        guard results.count >= Self.minimumResultCount else { throw APIError(message: L.t("web_no_results")) }
        return Array(results.prefix(resultLimit))
    }

    static func fetchText(_ url: URL) async throws -> WebHit {
        var req = URLRequest(url: url)
        req.setValue(searchUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.timeoutInterval = APITimeout.webPageRequest
        let (data, resp) = try await HTTP.data(req, using: URLSession.shared)
        try HTTP.ensureSuccess(resp)
        guard let html = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self).nilIfEmpty else {
            throw APIError(message: L.t("web_fetch_failed"))
        }
        var t = html
        t = t.replacingOccurrences(of: "<(script|style|noscript|svg|header|footer|nav)[\\s\\S]*?</\\1>",
                                  with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "&[a-zA-Z#0-9]+;", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageTitle = firstMatch(html, pattern: "<title[^>]*>([^<]{3,140})</title>")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? url.lastPathComponent
        if t.count > maxTextChars { t = String(t.prefix(maxTextChars)) }
        guard t.count > minTextChars else { throw APIError(message: L.t("web_fetch_failed")) }
        return WebHit(title: decodeEntities(pageTitle), url: url.absoluteString, domain: domain(of: url), text: t)
    }

    static func makeAnswerRequest(baseURL: String, key: String, model: String,
                                  question: String, hits: [WebHit],
                                  history: [ChatMessage] = []) throws -> URLRequest {
        var context = ""
        let transcript = ConversationTranscript.withoutTheNewestQuestion(from: history)
        if !transcript.isEmpty {
            context += "## Bisheriger Verlauf der Unterhaltung (nur zur Einordnung der Frage, nicht als Quelle)\n\(transcript)\n\n"
        }
        for (index, hit) in hits.enumerated() {
            context += hit.sourceBlock(numbered: index + 1)
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": researchInstructions()],
                ["role": "user", "content": context + "## Frage\n" + question],
            ],
        ]
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.researchRequest)
    }

    private static func resolvedHref(_ rawHref: String) -> String {
        guard rawHref.hasPrefix("//duckduckgo.com/l/") || rawHref.contains("uddg="),
              let comps = URLComponents(string: "https:" + rawHref.dropFirst(2)),
              let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
              let decoded = uddg.removingPercentEncoding else { return rawHref }
        return decoded
    }

    private static func firstMatch(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&bdquo;": "„"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    private static func researchInstructions() -> String {
        "Du bist ein Recherche-Assistent. Beantworte die Frage des Nutzers AUSSCHLIESSLICH auf Basis "
            + "der angegebenen Web-Quellen. Ein etwaiger Block 'Bisheriger Verlauf der Unterhaltung' dient nur "
            + "dazu, Rückverweise wie 'dazu', 'damit' oder 'das Bild' aufzulösen; seine Aussagen sind keine Quelle "
            + "und dürfen nicht als Fakten wiederholt werden, es sei denn, eine Quelle bestätigt sie. "
            + "Zitiere jede Aussage mit der Quellennummer in eckigen Klammern, "
            + "z. B. [1] oder [2][3]. Nutze mindestens zwei Quellen fuer die Kernantwort, wenn es sie gibt; wenn sich "
            + "Quellen widersprechen, nenne den Widerspruch kurz. Gibt es nur eine Quelle, nutze sie und sage das "
            + "in einem Halbsatz. Antworte in der Sprache der Frage, sachlich "
            + "und kompakt (max. 150 Woertern). Wenn die Quellen die Frage nicht beantworten, sage das ehrlich. "
            + "Strukturiere die Antwort übersichtlich: kurze Absätze durch Leerzeilen getrennt, mehrere Punkte "
            + "als Aufzählung (- am Zeilenanfang), Schlüsselbegriffe und Zahlen **fett**, keine Markdown-Überschriften."
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
