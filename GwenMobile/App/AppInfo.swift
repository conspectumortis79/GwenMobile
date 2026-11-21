import GwenMobileKit
import Foundation

struct AppInfo: Equatable, Sendable {
    var version: String
    var build: String?

    static let installed = AppInfo(reading: .main)

    init(reading bundle: Bundle) {
        self.init(info: bundle.infoDictionary ?? [:])
    }

    init(info: [String: Any]) {
        version = Self.text(info["CFBundleShortVersionString"]) ?? "1.0"
        build = Self.text(info["CFBundleVersion"])
    }

    var versionLine: String {
        guard let build, build != version else { return version }
        return L.fmt2("app_info_version_value", version, build)
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
