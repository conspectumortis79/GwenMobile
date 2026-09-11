import Foundation

enum AnswerHTML {
    static func document(text: String, sources: [WebSource], heading: String, title: String,
                         meta: String, language: String) -> String {
        let docTitle = escape(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "GwenMobile" : title)
        return "<!doctype html>\n<html lang=\"\(escape(language))\">\n<head>\n"
            + "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
            + "<title>\(docTitle)</title>\n<style>\(stylesheet)</style>\n</head>\n<body>\n<article>\n"
            + blocks(in: text, sources: sources) + "\n"
            + sourceList(sources: sources, heading: heading) + "\n"
            + (meta.isEmpty ? "" : "<p class=\"meta\">\(escape(meta))</p>\n")
            + "</article>\n</body>\n</html>\n"
    }

    static func metaLine(model: String?, elapsed: Double?, time: String?) -> String {
        var parts: [String] = []
        if let model {
            parts.append(elapsed.map { "\(model) · \(String(format: "%.1f", $0)) s" } ?? model)
        }
        if let time { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    static func blocks(in text: String, sources: [WebSource]) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var items: [String] = []
        var listTag = ""
        var listHeldOpen = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>" + paragraph.map { inline($0, sources: sources) }.joined(separator: "\n") + "</p>")
            paragraph = []
        }

        func flushList() {
            guard !items.isEmpty else { return }
            html.append("<\(listTag)>" + items.map { "<li>\($0)</li>" }.joined(separator: "") + "</\(listTag)>")
            items = []
            listTag = ""
            listHeldOpen = false
        }

        func openList(_ tag: String) {
            if listTag != tag { flushList(); listTag = tag }
            listHeldOpen = false
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                if items.isEmpty { flushList() } else { listHeldOpen = true }
                continue
            }
            if let level = headingLevel(trimmed) {
                flushParagraph(); flushList()
                let body = String(trimmed.dropFirst(level).drop(while: { $0 == "#" || $0 == " " }))
                html.append("<h\(level + 1)>" + inline(body, sources: sources) + "</h\(level + 1)>")
                continue
            }
            if let body = unorderedBody(trimmed) {
                flushParagraph()
                if listHeldOpen && listTag != "ul" { flushList() }
                openList("ul")
                items.append(inline(body, sources: sources))
                continue
            }
            if let body = orderedBody(trimmed) {
                flushParagraph()
                if listHeldOpen && listTag != "ol" { flushList() }
                openList("ol")
                items.append(inline(body, sources: sources))
                continue
            }
            flushList()
            paragraph.append(trimmed)
        }
        flushParagraph(); flushList()
        return html.joined(separator: "\n")
    }

    static func inline(_ raw: String, sources: [WebSource] = []) -> String {
        var spans: [String] = []
        var text = protectCodeSpans(raw, spans: &spans)
        text = escape(text)
        text = markdownLinks(text)
        text = footnoteRefs(text, count: sources.count)
        text = emphasis(text)
        return restoreCodeSpans(text, spans: spans)
    }

    static func sourceList(sources: [WebSource], heading: String) -> String {
        guard !sources.isEmpty else { return "" }
        let items = sources.enumerated().map { index, source in
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty ? source.domain : title
            return "<li id=\"quelle-\(index + 1)\"><a href=\"\(escapeForAttribute(safeURL(source.url)))\">"
                + escape(label) + "</a> <span class=\"domain\">" + escape(source.domain) + "</span></li>"
        }.joined(separator: "")
        return "<section class=\"quellen\"><h3>" + escape(heading) + "</h3><ol>" + items + "</ol></section>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeForAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let stylesheet = """
     :root { color-scheme: light dark; }
     body { margin: 0; padding: 28px 20px 44px; background: #fff; color: #16161a;
            font: 17px/1.6 -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
     article { max-width: 46rem; margin: 0 auto; }
     p { margin: 0 0 14px; white-space: pre-wrap; overflow-wrap: break-word; }
     h2, h3, h4 { margin: 22px 0 8px; line-height: 1.3; }
     ul, ol { margin: 0 0 16px; padding-left: 22px; }
     li { margin: 0 0 6px; }
     code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em;
            background: rgba(118, 118, 128, 0.16); padding: 1px 5px; border-radius: 5px; }
     a { color: #0a7cff; text-decoration: none; }
     .quellen { margin-top: 26px; border-top: 1px solid rgba(60, 60, 67, 0.18); padding-top: 14px; }
     .quellen h3 { margin-top: 0; font-size: 13px; letter-spacing: 0.4px; color: #6b6b70; }
     .quellen ol { font-size: 15px; }
     .domain { color: #8e8e93; font-size: 13px; }
     .meta { margin-top: 22px; color: #8e8e93; font-size: 13px; }
     @media (prefers-color-scheme: dark) {
       body { background: #111114; color: #f2f2f7; }
       .quellen { border-top-color: rgba(235, 235, 245, 0.22); }
     }
     @media print { body { padding: 0; } a { color: inherit; } }
    """

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes <= 3, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func unorderedBody(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedBody(_ line: String) -> String? {
        guard let edge = line.firstIndex(of: ".") ?? line.firstIndex(of: ")"),
              line[line.startIndex..<edge].allSatisfy({ $0.isNumber }),
              !line[line.startIndex..<edge].isEmpty,
              line[line.index(after: edge)...].first == " " else { return nil }
        return String(line[line.index(edge, offsetBy: 2)...])
    }

    private static func protectCodeSpans(_ text: String, spans: inout [String]) -> String {
        transform(text, #"`([^`\n]+)`"#) { match, source in
            spans.append(substring(of: source, at: match.range(at: 1)))
            return "\u{0001}\(spans.count - 1)\u{0002}"
        }
    }

    private static func restoreCodeSpans(_ text: String, spans: [String]) -> String {
        var out = text
        for (index, span) in spans.enumerated() {
            out = out.replacingOccurrences(of: "\u{0001}\(index)\u{0002}", with: "<code>" + escape(span) + "</code>")
        }
        return out
    }

    private static func markdownLinks(_ text: String) -> String {
        transform(text, #"\[([^\]\n]{1,200})\]\((https?:[^)\s]{1,500})\)"#) { match, source in
            "<a href=\"\(substring(of: source, at: match.range(at: 2)))\">"
                + substring(of: source, at: match.range(at: 1)) + "</a>"
        }
    }

    private static func footnoteRefs(_ text: String, count: Int) -> String {
        guard count > 0 else { return text }
        return transform(text, #"\[(\d{1,2})\]"#) { match, source in
            let whole = substring(of: source, at: match.range)
            guard let number = Int(substring(of: source, at: match.range(at: 1))),
                  (1...count).contains(number) else { return whole }
            return "<a href=\"#quelle-\(number)\">[\(number)]</a>"
        }
    }

    private static func emphasis(_ text: String) -> String {
        let bold = transform(text, #"\*\*([^*\n]+)\*\*"#) { match, source in
            "<strong>" + substring(of: source, at: match.range(at: 1)) + "</strong>"
        }
        let italic = transform(bold, #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) { match, source in
            "<em>" + substring(of: source, at: match.range(at: 1)) + "</em>"
        }
        return transform(italic, #"~~([^~\n]+)~~"#) { match, source in
            "<del>" + substring(of: source, at: match.range(at: 1)) + "</del>"
        }
    }

    private static func safeURL(_ raw: String) -> String {
        raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "#"
    }

    private static func substring(of text: String, at range: NSRange) -> String {
        guard let region = Range(range, in: text) else { return "" }
        return String(text[region])
    }

    private static func transform(_ text: String, _ pattern: String,
                                  by maker: (_ match: NSTextCheckingResult, _ source: String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += maker(match, text)
            cursor = match.range.location + match.range.length
        }
        out += source.substring(with: NSRange(location: cursor, length: source.length - cursor))
        return out
    }
}
