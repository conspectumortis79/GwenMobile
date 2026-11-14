import GwenMobileKit
import Foundation

extension ModelTranslation {
    static func makeRequest(_ job: TranslationJob, credentials: TranslationCredentials) throws -> URLRequest {
        try QwenAPI.makeRequest(baseURL: credentials.baseURL, key: credentials.apiKey,
                                model: credentials.model,
                                messages: [ChatMessage(role: .user, text: job.text)],
                                imageData: [], stream: false,
                                system: prompt(for: job), thinking: credentials.thinking,
                                extra: ["tools": ToolRouter.translationTools(),
                                        "tool_choice": ToolRouter.forcedChoice])
    }

    static func translate(_ job: TranslationJob, credentials: TranslationCredentials) async throws -> String {
        guard credentials.isUsable else { throw TranslationProblem.model("no api access") }
        let request = try makeRequest(job, credentials: credentials)
        let data: Data
        do {
            data = try await HTTP.jsonData(request)
        } catch {
            throw TranslationProblem.model(error.localizedDescription)
        }
        guard let raw = translation(from: data) else {
            throw TranslationProblem.model(L.t("translate_failed"))
        }
        let text = cleaned(raw).trimmed
        guard !text.isEmpty else {
            throw TranslationProblem.model(L.t("translate_failed"))
        }
        return text
    }
}

extension TranslationFlow {
    static func run(_ job: TranslationJob, credentials: TranslationCredentials) async throws
        -> TranslationResult {
        #if DEBUG
        if let runOverride { return try await runOverride(job, credentials) }
        #endif
        guard !job.isEmpty else { throw TranslationProblem.nothingToTranslate }
        let status = await OnDeviceTranslation.status(for: job)
        if status == .ready {
            let carried = job.withSource(OnDeviceTranslation.sourceCode(for: job))
            do {
                let text = try await OnDeviceTranslation.translate(job)
                    .trimmed
                if !text.isEmpty {
                    return TranslationResult(text: text, signature: signature(onDevice: true, job: carried),
                                             onDevice: true)
                }
            } catch let problem as TranslationProblem {
                guard credentials.isUsable else { throw problem }
            }
        } else if !credentials.isUsable {
            throw TranslationProblem.from(status: status, target: job.targetCode)
        }
        let text = try await ModelTranslation.translate(job, credentials: credentials)
        return TranslationResult(text: text, signature: signature(onDevice: false, job: job), onDevice: false)
    }
}
