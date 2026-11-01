import GwenMobileKit
import Foundation

enum RateLimitRetry {
    static let attempts = 3
    static let backoff = Duration.milliseconds(900)

    static func run<T: Sendable>(attempts: Int = attempts, backoff: Duration = backoff,
                                 _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await body()
            } catch let error as APIError where error.isRateLimited && attempt < attempts {
                let wait = backoff * attempt
                flowMark("DROSSEL versuch=\(attempt) warte=\(wait) "
                         + TextLine.oneLine(error.message, limit: 80))
                try await Task.sleep(for: wait)
                attempt += 1
            }
        }
    }
}
