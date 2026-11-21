import Foundation

public enum EntityKey {
    public static let shortLength = 8

    public static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(shortLength)).lowercased()
    }

    public static func normalized(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "#", with: "")
    }
}
