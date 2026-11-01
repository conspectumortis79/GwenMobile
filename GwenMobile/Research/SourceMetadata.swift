import GwenMobileKit
import Foundation

struct SourceMetadata: Equatable, Sendable {
    static let scanLimit = 200_000
    static let kindLimit = 6

    var published: String?
    var author: String?
    var kinds: [String] = []
    var imprint = false
    var paidLinks = false

    func dossier(risk: SourceGuard.Verdict) -> String {
        let fields = presentFields.joined(separator: " · ")
        var line = fields.isEmpty
            ? PromptLibrary.field("web_source_meta", "empty")
            : PromptLibrary.field("web_source_meta", "line", ["fields": fields])
        let reasons = risk.reasons.map(\.promptText).filter { !$0.isEmpty }
        guard !reasons.isEmpty else { return line }
        line += " " + PromptLibrary.field("web_source_meta", "warning",
                                          ["reasons": reasons.joined(separator: ", ")])
        return line
    }

    private var presentFields: [String] {
        var fields: [String] = []
        if let published { fields.append("date \(published)") }
        if let author { fields.append("author \(author)") }
        if !kinds.isEmpty { fields.append("type \(kinds.joined(separator: ", "))") }
        if imprint { fields.append("imprint found") }
        if paidLinks { fields.append("paid links") }
        return fields
    }

    static func from(html: String) -> SourceMetadata {
        let scan = String(html.prefix(scanLimit))
        var metadata = SourceMetadata()
        metadata.published = published(in: scan)
        metadata.author = author(in: scan)
        metadata.kinds = kinds(in: scan)
        let lower = scan.lowercased()
        metadata.imprint = lower.contains("impressum") || lower.contains("imprint")
        metadata.paidLinks = firstMatch(in: scan, pattern: "(rel=[\"'][^\"']*\\bsponsored\\b)") != nil
        return metadata
    }

    private static func published(in html: String) -> String? {
        let patterns = [
            "\"datePublished\"\\s*:\\s*\"([^\"]{4,40})\"",
            "\"dateModified\"\\s*:\\s*\"([^\"]{4,40})\"",
            "<meta[^>]+(?:property|name)=[\"'](?:article:published_time|datepublished|pubdate|"
                + "sailthru\\.date|date|dc\\.date(?:\\.issued)?)[\"'][^>]*content=[\"']([^\"']{4,40})[\"']",
            "<meta[^>]+content=[\"']([^\"']{4,40})[\"'][^>]*(?:property|name)=[\"']"
                + "(?:article:published_time|datepublished|pubdate|sailthru\\.date|date|dc\\.date(?:\\.issued)?)[\"']",
        ]
        guard let raw = patterns.lazy.compactMap({ firstMatch(in: html, pattern: $0) }).first else { return nil }
        return shortened(raw)
    }

    private static func author(in html: String) -> String? {
        let patterns = [
            "\"author\"\\s*:\\s*\\{[^{}]{0,240}?\"name\"\\s*:\\s*\"([^\"]{2,80})\"",
            "<meta[^>]+name=[\"']author[\"'][^>]*content=[\"']([^\"']{2,80})[\"']",
            "<meta[^>]+content=[\"']([^\"']{2,80})[\"'][^>]*name=[\"']author[\"']",
            "<meta[^>]+property=[\"']article:author[\"'][^>]*content=[\"']([^\"']{2,80})[\"']",
        ]
        return patterns.lazy.compactMap { firstMatch(in: html, pattern: $0) }.first
            .map { HTMLEntities.decoded($0).trimmed }
    }

    private static func kinds(in html: String) -> [String] {
        var found: [String] = []
        for block in jsonLdBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            for entity in entities(in: root) {
                for value in typeNames(entity["@type"]) where !found.contains(value) {
                    found.append(value)
                }
            }
            if found.count >= kindLimit { break }
        }
        if found.isEmpty,
           let og = firstMatch(in: html, pattern: "<meta[^>]+property=[\"']og:type[\"'][^>]*content=[\"']([^\"']{1,60})[\"']") {
            let clean = og.prefix { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
            if !clean.isEmpty { found.append(String(clean.prefix(40))) }
        }
        return Array(found.prefix(kindLimit))
    }

    private static func jsonLdBlocks(in html: String) -> [String] {
        let pattern = "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>"
        guard let regex = regexCache.regex(pattern) else { return [] }
        let source = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
    }

    static func entities(in root: Any) -> [[String: Any]] {
        if let object = root as? [String: Any] {
            if let graph = object["@graph"] as? [Any] {
                return graph.compactMap { $0 as? [String: Any] }
            }
            return [object]
        }
        if let list = root as? [Any] { return list.compactMap { $0 as? [String: Any] } }
        return []
    }

    private static func typeNames(_ value: Any?) -> [String] {
        let raw: [String]
        if let text = value as? String {
            raw = [text]
        } else if let list = value as? [String] {
            raw = list
        } else {
            return []
        }
        return raw.filter { name in
            (3...30).contains(name.count)
                && name.first?.isLetter == true
                && name.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    private static func shortened(_ raw: String) -> String {
        let value = raw.trimmed
        if value.count >= 10, value.dropFirst(10).first == "T" {
            return String(value.prefix(10))
        }
        return String(value.prefix(40))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = regexCache.regex(pattern) else { return nil }
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              match.numberOfRanges > 1 else { return nil }
        return source.substring(with: match.range(at: 1))
    }

    private static let regexCache = RegexCache(options: [.caseInsensitive])
}
