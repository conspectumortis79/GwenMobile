import GwenMobileKit
import Foundation

enum ScanAnswers {
    static func instruction(for request: ScanRequest) -> String {
        L.t(request.kind.taskKey)
    }

    static func fileName(for kind: ScanKind, date: Date) -> String {
        "\(L.t(kind.fileNameKey)) \(Formatters.fileStamp(date)).pdf"
    }

    static var cancelled: String { L.t("scan_cancelled") }

    static var failed: String { L.t("scan_failed") }

    static var unavailable: String { L.t("scan_unavailable") }

    static func joined(_ text: String, instruction: String) -> String {
        let body = text.trimmed
        return body.isEmpty ? instruction : body + "\n\n" + instruction
    }

    static func injectInstruction(into messages: inout [ChatMessage], for request: ScanRequest) {
        guard let speaker = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages[speaker].text = joined(messages[speaker].text, instruction: instruction(for: request))
    }
}
