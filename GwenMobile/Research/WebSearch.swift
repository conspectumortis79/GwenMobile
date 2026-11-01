import GwenMobileKit
import Foundation

struct WebHit: Sendable {
    var title: String
    var url: String
    var domain: String
    var text: String
    var metadata: SourceMetadata = SourceMetadata()
    var risk: SourceGuard.Verdict = SourceGuard.Verdict()

    func sourceBlock(numbered number: Int, copyOf origin: Int? = nil) -> String {
        let duplicate = origin.map {
            PromptLibrary.field("web_source_meta", "duplicate", ["number": String($0)]) + "\n"
        } ?? ""
        return PromptLibrary.text("web_source_block", ["number": String(number), "title": title,
                                                       "domain": domain, "origin": duplicate,
                                                       "check": metadata.dossier(risk: risk) + "\n",
                                                       "text": text]) + "\n\n"
    }
}

enum WebSearch {
    static let searchUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let resultLimit = 5
    static let maxAnswerImages = 2
    static let maxTextChars = 4000
    static let minTextChars = 200

    static let searchEndpoint = "https://html.duckduckgo.com/html/"

    static let ownRootDomain: String = {
        guard let endpoint = URL(string: searchEndpoint) else { return "" }
        return root(ofDomain: domain(of: endpoint))
    }()

    static func isOwnResult(_ url: URL) -> Bool {
        root(ofDomain: domain(of: url)) == ownRootDomain
    }

    static func domain(of url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst("www.".count)) : host
    }

    private static let countrySecondLevels: Set<String> = ["co", "com", "org", "net", "gov", "ac", "edu"]

    static func root(ofDomain domain: String) -> String {
        let labels = domain.lowercased().split(separator: ".").map(String.init)
            .filter { !$0.isEmpty && $0 != "www" }
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let suffix = labels[labels.count - 1]
        let secondLevel = labels[labels.count - 2]
        let kept = suffix.count == 2 && countrySecondLevels.contains(secondLevel) ? 3 : 2
        return labels.suffix(kept).joined(separator: ".")
    }

    #if DEBUG
    static func search(_ query: String, region: String? = nil) async throws -> [URL] {
        let urls = try await searchURLs(query, region: region)
        guard !urls.isEmpty else { throw APIError(message: L.t("web_no_results")) }
        return urls
    }
    #endif

    static func pageRequest(_ url: URL, accept: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(searchUA, forHTTPHeaderField: "User-Agent")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        req.timeoutInterval = APITimeout.webPageRequest
        return req
    }

    static func searchRequest(_ query: String, region: String? = nil) throws -> URLRequest {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))),
              !query.trimmed.isEmpty else {
            throw APIError(message: L.t("web_bad_query"))
        }
        var address = "\(searchEndpoint)?q=\(enc)"
        if let region, let code = regionTag(region) {
            address += "&kl=\(code)"
        }
        guard let url = URL(string: address) else { throw APIError(message: L.t("web_bad_query")) }
        return pageRequest(url)
    }

    private static let regionCodes: [String: [String]] = [
        "ar": ["ar-es"], "at": ["at-de"], "au": ["au-en"], "be": ["be-fr", "be-nl"], "bg": ["bg-bg"],
        "br": ["br-pt"], "ca": ["ca-en", "ca-fr"], "ch": ["ch-de", "ch-fr", "ch-it"], "cl": ["cl-es"],
        "cn": ["cn-zh"], "co": ["co-es"], "cz": ["cz-cs"], "de": ["de-de"], "dk": ["dk-da"], "ee": ["ee-et"],
        "es": ["es-es"], "fi": ["fi-fi"], "fr": ["fr-fr"], "gb": ["uk-en"], "gr": ["gr-el"], "hk": ["hk-tzh"],
        "hr": ["hr-hr"], "hu": ["hu-hu"], "id": ["id-id", "id-en"], "ie": ["ie-en"], "il": ["il-he"],
        "in": ["in-en"], "it": ["it-it"], "jp": ["jp-jp"], "kr": ["kr-kr"], "lt": ["lt-lt"],
        "lv": ["lv-lv"], "mx": ["mx-es"], "my": ["my-ms", "my-en"], "nl": ["nl-nl"], "no": ["no-no"],
        "nz": ["nz-en"], "pe": ["pe-es"], "ph": ["ph-en", "ph-tl"], "pl": ["pl-pl"], "pt": ["pt-pt"],
        "ro": ["ro-ro"], "ru": ["ru-ru"], "se": ["se-sv"], "sg": ["sg-en"], "si": ["sl-sl"], "sk": ["sk-sk"],
        "th": ["th-th"], "tr": ["tr-tr"], "tw": ["tw-tzh"], "ua": ["ua-uk"], "us": ["us-en", "us-es"],
        "ve": ["ve-es"], "vn": ["vn-vi"], "za": ["za-en"],
    ]

    static func regionTag(_ region: String, language: AppLanguage = L.lang) -> String? {
        guard let codes = regionCodes[region.trimmed.lowercased()] else { return nil }
        return codes.first { $0.hasSuffix("-" + language.rawValue) } ?? codes.first
    }

    private static let resultHref = try? NSRegularExpression(pattern: "result__a[^>]*href=\"([^\"]+)\"[^>]*>(?:[^<]{4,160})")
    private static let pageTitle = try? NSRegularExpression(pattern: "<title[^>]*>([^<]{3,140})</title>",
                                                           options: [.caseInsensitive])

    static func searchURLs(_ query: String, region: String? = nil) async throws -> [URL] {
        let (data, resp) = try await HTTP.data(searchRequest(query, region: region))
        try HTTP.ensureSuccess(resp)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        var results: [URL] = []
        var seenDomains = Set<String>()
        guard let re = resultHref else { return [] }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = resolvedHref(ns.substring(with: m.range(at: 1)))
            guard let u = URL(string: href), let scheme = u.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", u.host != nil else { continue }
            let clean = domain(of: u)
            guard !SourceGate.local.isBlocked(u) else {
                flowMark("SUCHE abgelehnt domain=\(clean)")
                continue
            }
            let root = root(ofDomain: clean)
            guard !isOwnResult(u), !seenDomains.contains(root) else { continue }
            seenDomains.insert(root)
            results.append(u)
            if results.count >= resultLimit { break }
        }
        return results
    }

    static func fetchText(_ url: URL) async throws -> WebHit {
        let (data, resp) = try await HTTP.data(pageRequest(url, accept: "text/html,application/xhtml+xml"))
        try HTTP.ensureSuccess(resp)
        let html = String(decoding: data, as: UTF8.self)
        let stripped = HTMLText.plain(html, hiding: HTMLText.pageNoiseBlocks)
        var t = stripped
        let pageTitle = firstMatch(html, regex: Self.pageTitle)?
            .trimmed ?? url.lastPathComponent
        if t.count > maxTextChars { t = String(t.prefix(maxTextChars)) }
        guard t.count > minTextChars else { throw APIError(message: L.t("web_fetch_failed")) }
        let clean = domain(of: url)
        return WebHit(title: HTMLEntities.decoded(pageTitle), url: url.absoluteString, domain: clean, text: t,
                      metadata: SourceMetadata.from(html: html),
                      risk: SourceGuard.assess(url, reported: SourceReports.shared.isReported(clean)))
    }

    static func makeAnswerRequest(baseURL: String, key: String, model: String,
                                  question: String, hits: [WebHit],
                                  history: [ChatMessage] = [],
                                  images: [Data] = [],
                                  length: AnswerLength = .compact,
                                  thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(Prompt.Research.webAnswer(length: length,
                                                                                      sourceNote: SourceReview.coverageNote(hits: hits))),
                                        ChatPayload.user(answerContext(question: question, hits: hits,
                                                                       history: history, images: images))],
                             stream: true, thinking: thinking,
                             timeout: APITimeout.researchRequest)
    }

    static func answerContext(question: String, hits: [WebHit], history: [ChatMessage],
                              images: [Data] = []) -> Any {
        var context = ""
        let transcript = ConversationTranscript.withoutTheNewestQuestion(from: history)
        if !transcript.isEmpty {
            context += PromptLibrary.text("web_earlier_conversation", ["transcript": transcript]) + "\n\n"
        }
        let groups = SourceSimilarity.clusters(hits)
        for (index, hit) in hits.enumerated() {
            context += hit.sourceBlock(numbered: index + 1,
                                       copyOf: SourceSimilarity.originNumber(of: index, groups: groups))
        }
        let text = context + PromptLibrary.text("web_question", ["question": question])
        guard !images.isEmpty else { return text }
        var parts: [[String: Any]] = [ChatPayload.text(text)]
        for image in images.prefix(maxAnswerImages) {
            if let part = ChatPayload.image(image) { parts.append(part) }
        }
        return parts
    }

    static func resolvedHref(_ rawHref: String) -> String {
        let target = rawHref.hasPrefix("//") ? "https:" + rawHref.dropFirst(2) : rawHref
        guard let comps = URLComponents(string: target),
              let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
              !uddg.isEmpty else { return rawHref }
        return uddg
    }

    private static func firstMatch(_ s: String, regex: NSRegularExpression?) -> String? {
        let ns = s as NSString
        guard let regex, let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
