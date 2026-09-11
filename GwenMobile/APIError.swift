import Foundation

struct APIError: LocalizedError, Sendable {
    var message: String
    var status: Int?
    var recoveredText: String?

    var errorDescription: String? { message }

    init(message: String, status: Int? = nil, recoveredText: String? = nil) {
        self.message = message
        self.status = status
        self.recoveredText = recoveredText
    }
}

enum APITimeout {
    static let chatRequest: TimeInterval = 90
    static let researchRequest: TimeInterval = 300
    static let imageRequest: TimeInterval = 300
    static let modelsRequest: TimeInterval = 30
    static let webPageRequest: TimeInterval = 20
    static let streamIdle: TimeInterval = 90
    static let streamResource: TimeInterval = 900
}

enum APIEndpoint {
    static let chatCompletions = "/chat/completions"
    static let models = "/models"
}
