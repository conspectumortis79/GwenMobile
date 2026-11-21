import GwenMobileKit
import Foundation
import SwiftUI

enum MarkdownRenderer {
    private static let ruleMark = "\u{2500}"
    private static let ruleWidth = 10

    static func inline(_ text: String) -> AttributedString {
        parsed(text)
    }

    static func answer(_ text: String, phoneLinks: Bool = true) -> AttributedString {
        let attr = parsed(normalizedBlocks(text))
        return phoneLinks ? linkingPhones(in: attr) : attr
    }

    static func normalizedBlocks(_ text: String) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(normalizedLine(String(line)))
        }
        return lines.joined(separator: "\n")
    }

    private static func parsed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func normalizedLine(_ line: String) -> String {
        if isRule(line) { return String(repeating: ruleMark, count: ruleWidth) }
        if let heading = headingLine(line) { return heading }
        if let bullet = bulletLine(line) { return bullet }
        return line
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmed
        guard trimmed.count >= 3, let marker = trimmed.first,
              marker == "-" || marker == "*" || marker == "_" else { return false }
        var count = 0
        for character in trimmed {
            if character == marker { count += 1 } else if character != " " { return false }
        }
        return count >= 3
    }

    private static func headingLine(_ line: String) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        let hashes = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let after = rest.dropFirst(hashes)
        guard hashes > 1 || after.first == " " || after.first == "\t" else { return nil }
        var title = after.trimmed
        while title.hasSuffix("#") { title.removeLast() }
        title = title.trimmed
        guard !title.isEmpty else { return nil }
        guard !title.contains("**") else { return String(indent) + title }
        return String(indent) + "**" + title + "**"
    }

    private static func bulletLine(_ line: String) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        guard let marker = rest.first, marker == "*" || marker == "+" || marker == "-" else { return nil }
        let after = rest.dropFirst()
        guard after.first == " " || after.first == "\t" else { return nil }
        let body = after.drop { $0 == " " || $0 == "\t" }
        guard !body.isEmpty else { return nil }
        return String(indent) + "- " + body
    }

    private static func linkingPhones(in attr: AttributedString) -> AttributedString {
        var attr = attr
        let plain = String(attr.characters)
        for link in PhoneLinks.matches(in: plain).reversed() {
            guard let range = Range(link.range, in: attr),
                  let url = link.number.telURL,
                  attr[range].runs.allSatisfy({ $0.link == nil }) else { continue }
            attr[range].link = url
            attr[range].foregroundColor = .blue
            attr[range].underlineStyle = .single
        }
        let marked = attr.runs.filter { $0.link?.scheme?.lowercased() == "tel" }.map(\.range)
        for range in marked {
            attr[range].foregroundColor = .blue
            attr[range].underlineStyle = .single
        }
        return attr
    }
}
