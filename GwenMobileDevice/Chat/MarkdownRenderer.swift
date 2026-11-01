@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation
import SwiftUI

enum MarkdownRenderer {

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    static func inline(_ text: String, phoneLinks: Bool) -> AttributedString {
        let attr = inline(text)
        return phoneLinks ? linkingPhones(in: attr) : attr
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
