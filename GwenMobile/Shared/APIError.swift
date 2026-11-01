import Foundation

public struct APIError: LocalizedError, Sendable {
    public var message: String
    public var status: Int?
    public var recoveredText: String?

    public var errorDescription: String? { message }

    public init(message: String, status: Int? = nil, recoveredText: String? = nil) {
        self.message = message
        self.status = status
        self.recoveredText = recoveredText
    }

    public var isRateLimited: Bool {
        let low = message.lowercased()
        return status == 429 || low.contains("throttling") || low.contains("too many requests")
            || low.contains("rate limit")
    }

    public var isInflightCreditLimit: Bool {
        guard status == 402 else { return false }
        let low = message.lowercased()
        return low.contains("in-flight") || low.contains("in flight")
    }
}

public enum APITimeout {
    public static let chatRequest: TimeInterval = 90
    public static let researchRequest: TimeInterval = 300
    public static let imageRequest: TimeInterval = 300
    public static let imageDownload: TimeInterval = 120
    public static let videoRequest: TimeInterval = 90
    public static let videoDownload: TimeInterval = 300
    public static let modelsRequest: TimeInterval = 30
    public static let probeRequest: TimeInterval = 20
    #if DEBUG
    public static let toolProbeRequest: TimeInterval = 60
    #endif
    public static let webPageRequest: TimeInterval = 20
    public static let pictureRequest: TimeInterval = 25
    public static let streamIdle: TimeInterval = 90
    public static let streamResource: TimeInterval = 900
}

public enum APIEndpoint {
    public static let chatCompletions = "/chat/completions"
    public static let models = "/models"
}
