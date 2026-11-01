import Foundation

public enum TextFolding {
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "„", with: "")
            .replacingOccurrences(of: "“", with: "")
            .trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
