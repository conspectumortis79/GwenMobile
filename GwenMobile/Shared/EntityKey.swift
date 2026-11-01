import Foundation

public enum EntityKey {
    public static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    public static func normalized(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "#", with: "")
    }
}
