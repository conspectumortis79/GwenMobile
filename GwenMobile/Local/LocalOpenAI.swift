import GwenMobileKit
import Foundation

enum LocalOpenAI {
    static func response(for request: URLRequest) async -> (Data, URLResponse)? {
        guard LocalEndpoint.isLocal(request.url) else { return nil }
        let path = LocalEndpoint.path(request)
        if path.hasSuffix(APIEndpoint.models) {
            return (LocalOpenAIResponse.models(LocalModelFiles().installedIDs()),
                    httpResponse(request, status: 200, type: "application/json"))
        }
        guard path.hasSuffix(APIEndpoint.chatCompletions) else {
            return (LocalOpenAIResponse.error(L.t("local_error_path")),
                    httpResponse(request, status: 404, type: "application/json"))
        }
        guard let body = request.httpBody else {
            return (LocalOpenAIResponse.error(LocalRequestError.empty.localizedDescription),
                    httpResponse(request, status: 400, type: "application/json"))
        }
        do {
            let parsed = try LocalChatRequest.parse(body)
            let result = try await LocalEngine.shared.run(parsed)
            return (LocalOpenAIResponse.completion(model: parsed.model, result: result),
                    httpResponse(request, status: 200, type: "application/json"))
        } catch {
            return (LocalOpenAIResponse.error(error.localizedDescription),
                    httpResponse(request, status: status(for: error), type: "application/json"))
        }
    }

    static func streamLines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let body = request.httpBody else { throw LocalRequestError.empty }
                    let parsed = try LocalChatRequest.parse(body)
                    var finish = "stop"
                    var called = false
                    var toolIndex = 0
                    let events = await LocalEngine.shared.stream(parsed)
                    for try await event in events {
                        try Task.checkCancellation()
                        switch event {
                        case .text(let text):
                            continuation.yield(LocalOpenAIResponse.chunk(model: parsed.model, text: text))
                        case .toolCall(let call):
                            called = true
                            continuation.yield(LocalOpenAIResponse.toolChunk(model: parsed.model, call: call,
                                                                            index: toolIndex))
                            toolIndex += 1
                        case .info(let info):
                            finish = info.finishReason
                        }
                    }
                    let reason = called ? "tool_calls" : (finish == "length" ? "length" : "stop")
                    continuation.yield(LocalOpenAIResponse.finalChunk(model: parsed.model, reason: reason))
                    continuation.yield(LocalOpenAIResponse.done())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func status(for error: Error) -> Int {
        if let api = error as? APIError { return api.status ?? 500 }
        if error is LocalRequestError { return 400 }
        if error is LocalEngineError { return 503 }
        return 500
    }

    private static func httpResponse(_ request: URLRequest, status: Int, type: String) -> URLResponse {
        HTTPURLResponse(url: request.url ?? URL(string: LocalEndpoint.baseURL)!,
                        statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": type])!
    }
}
