import GwenMobileKit
import Foundation

protocol ProductScanning: Sendable {
    func scan(baseURL: String, key: String, model: String, question: String, image: Data,
              thinking: ThinkingDirective) async throws -> ProductFinding?
}

struct VisionProductScanner: ProductScanning {
    static let maxTokens = 200
    static let scanAttempts = 2
    static let maxQuestionChars = ProductFinding.maxProductChars * 2

    static func toolChoice(attempt: Int) -> String {
        attempt <= 1 ? ToolRouter.forcedChoice : ToolRouter.automaticChoice
    }

    static func makeRequest(baseURL: String, key: String, model: String, question: String,
                            image: Data, thinking: ThinkingDirective,
                            toolChoice: String = ToolRouter.forcedChoice) throws -> URLRequest {
        guard let picture = ChatPayload.image(image) else {
            throw APIError(message: L.t("image_too_large"))
        }
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                                    messages: [ChatPayload.system(Prompt.Product.finding()),
                                               ChatPayload.user([ChatPayload.text(userText(question)), picture])],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             extra: ToolRouter.toolFields(maxTokens: maxTokens, tools: ToolRouter.productTools(),
                                                          toolChoice: toolChoice))
    }

    static func userText(_ question: String) -> String {
        let oneLine = TextLine.oneLine(question, limit: maxQuestionChars)
            .trimmed
        return oneLine.isEmpty ? L.t("product_scan_ask") : "\(L.t("product_scan_ask"))\n\(oneLine)"
    }

    static func reportCall(in data: Data) -> ToolCall? {
        ToolRouter.toolCalls(from: data).first { $0.name == ToolRouter.productTool }
    }

    func scan(baseURL: String, key: String, model: String, question: String, image: Data,
              thinking: ThinkingDirective) async throws -> ProductFinding? {
        for attempt in 1...max(1, Self.scanAttempts) {
            let choice = Self.toolChoice(attempt: attempt)
            let data = await Offload.orNilFlat { () -> Data? in
                do {
                    let req = try Self.makeRequest(baseURL: baseURL, key: key, model: model,
                                                   question: question, image: image, thinking: thinking,
                                                   toolChoice: choice)
                    return try await HTTP.jsonData(req)
                } catch {
                    flowMarkPersonal("PRODUKTSCAN abgelehnt versuch=\(attempt) wahl=\(choice) "
                                     + "meldung=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
                    return nil
                }
            }
            guard let data else { continue }
            guard let call = Self.reportCall(in: data) else {
                flowMarkPersonal("PRODUKTSCAN kein aufruf versuch=\(attempt) wahl=\(choice)")
                continue
            }
            guard let finding = ProductFinding(arguments: call.arguments) else {
                flowMarkPersonal("PRODUKTSCAN unbrauchbar versuch=\(attempt) "
                                 + "meldung=\(TextLine.oneLine(call.arguments, limit: 160))")
                continue
            }
            flowMarkPersonal("PRODUKTSCAN treffer versuch=\(attempt) befund=\(finding.traceLine)")
            return finding
        }
        return nil
    }
}
