import GwenMobileKit
import Foundation

struct PriceRegion: Equatable, Sendable {
    enum Source: String, Sendable {
        case named = "genannt"
        case device = "gerät"
        case located = "standort"
        case open = "offen"
    }

    static let unknown = PriceRegion(code: nil, source: .open)

    let code: String?
    let source: Source

    var isNarrowed: Bool { code != nil }
    var searchRegion: String? { code }

    var currencyCode: String? {
        guard let code else { return Locale.current.currency?.identifier }
        return Locale(identifier: "und_\(code)").currency?.identifier
    }

    var label: String? {
        guard let code else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
            ?? Locale(identifier: "en_US").localizedString(forRegionCode: code)
    }

    var traceLine: String {
        "land=\(code ?? "-") woher=\(source.rawValue) währung=\(currencyCode ?? "-")"
    }

    var promptLine: String? {
        guard let code, let label, let currency = currencyCode else { return nil }
        return PromptLibrary.text("price_region_line", ["label": label, "code": code,
                                                        "currency": currency]) + "\n\n"
    }

    private static let aliases: [String: String] = [
        "UK": "GB",
        "USA": "US",
        "ENGLAND": "GB",
        "GREAT BRITAIN": "GB",
        "HOLLAND": "NL",
    ]

    static func named(_ raw: String?) -> PriceRegion? {
        guard let text = normalised(raw), text.count >= 2 else { return nil }
        if let alias = aliases[text] { return PriceRegion(code: alias, source: .named) }
        if text.count == 2, isRegionCode(text) { return PriceRegion(code: text, source: .named) }
        guard let match = Locale.Region.isoRegions.first(where: { matchesName($0.identifier, with: text) })
        else { return nil }
        return PriceRegion(code: match.identifier, source: .named)
    }

    static func claimed(_ country: String?, in message: String) -> PriceRegion? {
        guard let region = named(country), let code = region.code else { return nil }
        let spoken = words(in: message)
        let namedWords = words(in: country ?? "")
        if !namedWords.isEmpty, namedWords.isSubset(of: spoken) { return region }
        if spoken.contains(code.lowercased()) { return region }
        for (alias, aliasCode) in aliases where aliasCode == code {
            let aliasWords = words(in: alias)
            if !aliasWords.isEmpty, aliasWords.isSubset(of: spoken) { return region }
        }
        for locale in [L.lang.locale, Locale.current, Locale(identifier: "en_US")] {
            guard let name = locale.localizedString(forRegionCode: code) else { continue }
            if spoken.contains(where: { hasPrefix(of: folded(name), in: $0) }) { return region }
        }
        return nil
    }

    static func device() -> PriceRegion {
        guard let code = Locale.current.region?.identifier, isRegionCode(code) else { return unknown }
        return PriceRegion(code: code, source: .device)
    }

    static func located(_ code: String?) -> PriceRegion {
        guard let code = normalised(code), isRegionCode(code) else { return unknown }
        return PriceRegion(code: code, source: .located)
    }

    private static func normalised(_ raw: String?) -> String? {
        let text = (raw ?? "").trimmed.uppercased()
        return text.isEmpty ? nil : text
    }

    private static func isRegionCode(_ code: String) -> Bool {
        Locale.Region.isoRegions.contains { $0.identifier == code }
    }

    private static func matchesName(_ code: String, with text: String) -> Bool {
        let wanted = folded(text)
        guard wanted.count > 2 else { return false }
        for locale in [L.lang.locale, Locale.current, Locale(identifier: "en_US")] {
            guard let name = locale.localizedString(forRegionCode: code) else { continue }
            if folded(name) == wanted { return true }
        }
        return false
    }

    private static func hasPrefix(of name: String, in word: String) -> Bool {
        let parts = name.split(separator: " ").map(String.init).filter { $0.count >= 4 }
        return parts.contains { word.hasPrefix($0) }
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    private static func folded(_ text: String) -> String {
        TextFolding.fold(text)
    }

}
