import GwenMobileKit
import Foundation

enum DocxText {
    static let documentPart = "word/document.xml"

    static func text(from data: Data) -> String? {
        guard let archive = ZipArchive(data: data),
              let xml = archive.data(for: documentPart) else { return nil }
        return text(fromDocumentXML: xml)
    }

    static func text(fromDocumentXML xml: Data) -> String? {
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = true
        let collector = Collector()
        parser.delegate = collector
        guard parser.parse() else { return nil }
        let trimmed = collector.body.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private final class Collector: NSObject, XMLParserDelegate {
        private(set) var body = ""
        private var insideText = false
        private var insideTabStops = false

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String]) {
            switch elementName {
            case "t":
                insideText = true
            case "p":
                endParagraph()
            case "tr":
                endParagraph()
            case "tabs":
                insideTabStops = true
            case "tab" where !insideTabStops:
                body += "\t"
            case "br", "cr":
                endLine()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "t":
                insideText = false
            case "tabs":
                insideTabStops = false
            case "tc":
                endCell()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard insideText else { return }
            body += string
        }

        private func endParagraph() {
            guard !body.isEmpty, !body.hasSuffix("\n"), !body.hasSuffix("\t") else { return }
            body += "\n"
        }

        private func endLine() {
            guard !body.isEmpty, !body.hasSuffix("\n") else { return }
            body += "\n"
        }

        private func endCell() {
            guard !body.isEmpty, !body.hasSuffix("\n"), !body.hasSuffix("\t") else { return }
            body += "\t"
        }
    }
}
