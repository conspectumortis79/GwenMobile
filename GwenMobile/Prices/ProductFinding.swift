import GwenMobileKit
import Foundation

struct ProductFinding: Equatable, Sendable {
    static let maxProductChars = 80
    static let maxBrandChars = 40
    static let maxPriceChars = 24
    static let maxCodeChars = 18

    var product = ""
    var brand = ""
    var price = ""
    var ean = ""

    var isUsable: Bool { !product.isEmpty }

    var identityTerms: [String] {
        let named = brand.isEmpty || product.localizedCaseInsensitiveContains(brand)
            ? "" : "\(brand) \(product)"
        var terms: [String] = []
        for term in [named, product, brand] where !term.isEmpty && !terms.contains(term) {
            terms.append(term)
        }
        return terms
    }

    var block: String {
        var lines: [String] = []
        if !product.isEmpty {
            lines.append(PromptLibrary.text("image_finding_product", ["value": product]))
        }
        if !brand.isEmpty {
            lines.append(PromptLibrary.text("image_finding_brand", ["value": brand]))
        }
        if !price.isEmpty {
            lines.append(PromptLibrary.text("image_finding_price", ["value": price]))
        }
        if !ean.isEmpty {
            lines.append(PromptLibrary.text("image_finding_ean", ["value": ean]))
        }
        guard !lines.isEmpty else { return "" }
        return PromptLibrary.text("image_finding_block",
                                  ["lines": lines.joined(separator: "\n")]) + "\n\n"
    }

    var traceLine: String {
        let joined = [product, brand, price, ean].filter { !$0.isEmpty }.joined(separator: " · ")
        return joined.isEmpty ? "-" : joined
    }
}

extension ProductFinding {
    private struct Payload: Decodable {
        var product: String?
        var brand: String?
        var price: String?
        var ean: String?
    }

    init?(arguments: String) {
        guard let data = arguments.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let finding = ProductFinding(
            product: Self.clipped(payload.product, Self.maxProductChars),
            brand: Self.clipped(payload.brand, Self.maxBrandChars),
            price: Self.clipped(payload.price, Self.maxPriceChars),
            ean: Self.clipped(payload.ean, Self.maxCodeChars))
        guard finding.isUsable else { return nil }
        self = finding
    }

    private static func clipped(_ raw: String?, _ limit: Int) -> String {
        guard let raw else { return "" }
        var text = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = unquoted(text.trimmed)
        return String(text.prefix(limit)).trimmed
    }

    private static func unquoted(_ raw: String) -> String {
        var text = raw
        for quote in ["\"", "'", "`", "“", "”", "„", "“"] {
            if text.hasPrefix(quote) { text = String(text.dropFirst(quote.count)) }
            if text.hasSuffix(quote) { text = String(text.dropLast(quote.count)) }
        }
        return text.trimmed
    }
}
