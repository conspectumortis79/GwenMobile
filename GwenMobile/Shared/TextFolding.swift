import Foundation

public enum TextFolding {
    public static func plain(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "„", with: "")
            .replacingOccurrences(of: "“", with: "")
            .trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    public static func fnv1a64(_ text: String) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 1_099_511_628_211
        }
        return value
    }
}
