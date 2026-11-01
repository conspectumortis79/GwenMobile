import Foundation

public enum LooseNumber {
    public static func value(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        guard let text = raw as? String else { return nil }
        return Double(folded(text))
    }

    public static func folded(_ raw: String) -> String {
        var text = raw.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        let commas = text.filter { $0 == "," }.count
        let dots = text.filter { $0 == "." }.count
        if commas == 0, dots == 0 { return text }
        if commas > 0, dots > 0 {
            let commaIsDecimal = text.reversed().first { $0 == "," || $0 == "." } == ","
            if commaIsDecimal {
                text = text.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
            return text
        }
        if commas > 0 {
            if commas > 1, isGroupedThousands(text, separator: ",") { return digits(of: text) }
            return text.replacingOccurrences(of: ",", with: ".")
        }
        if isGroupedThousands(text, separator: ".") { return digits(of: text) }
        return text
    }

    private static func isGroupedThousands(_ text: String, separator: Character) -> Bool {
        let body = text.hasPrefix("-") ? String(text.dropFirst()) : text
        let groups = body.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count >= 2, let first = groups.first, !first.isEmpty, first.count <= 3 else { return false }
        guard groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return false }
        if groups.count == 2, first == "0" { return false }
        return true
    }

    private static func digits(of text: String) -> String {
        text.filter { $0.isNumber || $0 == "-" }
    }
}
