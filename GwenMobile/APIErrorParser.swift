import Foundation

struct ErrorPayload: Decodable {
    var message: String?
    var code: String?
}

enum APIErrorParser {
    static func message(from data: Data, status: Int) -> String {
        message(from: String(data: data, encoding: .utf8) ?? "", status: status)
    }

    static func message(from body: String, status: Int) -> String {
        detail(of: body) ?? "HTTP \(status)"
    }

    private static func detail(of body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return truncated(body) }
        if let response = try? JSONDecoder().decode(ChatResponse.self, from: data), let error = response.error {
            return combined(error) ?? error.message
        }
        if let native = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           native.code != nil || native.message != nil {
            return combined(native) ?? native.code ?? native.message
        }
        return truncated(body)
    }

    private static func combined(_ payload: ErrorPayload) -> String? {
        guard let code = payload.code, let message = payload.message else { return nil }
        return "\(code): \(message)"
    }

    private static func truncated(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}
