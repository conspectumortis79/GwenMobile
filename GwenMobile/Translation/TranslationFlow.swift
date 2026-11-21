import GwenMobileKit
import Foundation

struct TranslationCredentials: Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var model: String
    var thinking: ThinkingDirective
    var keyOptional = false

    var isUsable: Bool {
        !baseURL.trimmed.isEmpty && (!apiKey.isEmpty || keyOptional)
            && !model.trimmed.isEmpty
    }
}

struct TranslationResult: Equatable {
    var text: String
    var signature: String
    var onDevice: Bool
}

enum ModelTranslation {
    static func prompt(for job: TranslationJob) -> String {
        let target = job.target.map { "\($0.code) (\($0.name(for: L.lang)))" } ?? job.targetCode
        let source = job.sourceCode.map { "\($0) (\(TranslationLanguages.named($0)))" }
        return PromptLibrary.text("translation_request",
                                  ["target": target,
                                   "source_clause": source.map { " The text is \($0)." } ?? "",
                                   "tool": ToolRouter.reportTranslationTool])
    }

    static func translation(from data: Data) -> String? {
        guard let object = ToolRouter.arguments(from: data, named: ToolRouter.reportTranslationTool),
              let raw = object["translation"] as? String else { return nil }
        let text = raw.trimmed
        return text.isEmpty ? nil : text
    }

    static func cleaned(_ raw: String) -> String {
        TextLine.unquoted(raw)
    }
}

enum TranslationFlow {
    #if DEBUG
    nonisolated(unsafe) static var runOverride: (@Sendable (TranslationJob, TranslationCredentials)
        async throws -> TranslationResult)?
    #endif

    static func busyLabel(for job: TranslationJob) -> String {
        L.fmt("translating", job.pairLabel)
    }

    static func signature(onDevice: Bool, job: TranslationJob) -> String {
        let origin = L.t(onDevice ? "translate_on_device" : "translate_via_model")
        return "\(origin) · \(job.pairLabel)"
    }
}
