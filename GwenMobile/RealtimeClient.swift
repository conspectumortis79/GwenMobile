import Foundation

struct RealtimeEvent: Sendable {
    var type: String = ""
    var transcript: String?
    var delta: String?
    var errorMessage: String?

    static func parse(_ s: String) -> RealtimeEvent {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return RealtimeEvent() }
        var ev = RealtimeEvent()
        ev.type = obj["type"] as? String ?? ""
        ev.transcript = obj["transcript"] as? String
        ev.delta = obj["delta"] as? String
        if let e = obj["error"] as? [String: Any] { ev.errorMessage = e["message"] as? String }
        return ev
    }
}

final class RealtimeClient: @unchecked Sendable {
    static let openTimeout: TimeInterval = 10
    static let sessionCreatedType = "session.created"
    static let errorType = "error"

    private let task: URLSessionWebSocketTask
    private let timeoutMessage: String
    private let fallbackError: String

    init(baseURL: String, model: String, key: String,
         timeoutMessage: String, fallbackError: String) throws {
        guard let url = Self.realtimeURL(baseURL: baseURL, model: model) else {
            throw APIError(message: L.t("bad_url"))
        }
        var req = URLRequest(url: url)
        HTTP.authorize(&req, key: key)
        let socket = URLSession.shared.webSocketTask(with: req)
        socket.resume()
        self.task = socket
        self.timeoutMessage = timeoutMessage
        self.fallbackError = fallbackError
    }

    static func opened(baseURL: String, model: String, key: String,
                       timeoutMessage: String, fallbackError: String) async throws -> RealtimeClient {
        let client = try RealtimeClient(baseURL: baseURL, model: model, key: key,
                                        timeoutMessage: timeoutMessage, fallbackError: fallbackError)
        do {
            try await client.connect()
        } catch {
            client.close()
            throw error
        }
        return client
    }

    static func realtimeURL(baseURL: String, model: String) -> URL? {
        var s = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        if let r = s.range(of: "/compatible-mode") { s = String(s[..<r.lowerBound]) }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: "\(s)/api-ws/v1/realtime?model=\(model)")
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }

    func connect() async throws {
        let deadline = Date().addingTimeInterval(Self.openTimeout)
        while Date() < deadline {
            let event = try await receive(until: deadline)
            if event.type == Self.errorType { throw APIError(message: event.errorMessage ?? fallbackError) }
            if event.type == Self.sessionCreatedType { return }
        }
        throw APIError(message: timeoutMessage)
    }

    func startSession(_ settings: [String: Any]) async throws {
        try await send(["type": "session.update", "session": settings])
    }

    func send(_ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let s = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(s))
    }

    func receive(until deadline: Date) async throws -> RealtimeEvent {
        let wait = max(0.5, deadline.timeIntervalSinceNow)
        let timeoutText = timeoutMessage
        let settled = Flag(false)
        let socket = task
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RealtimeEvent, Error>) in
            socket.receive { result in
                if settled.exchange(true) { return }
                switch result {
                case .success(let msg): cont.resume(returning: Self.event(from: msg))
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if settled.exchange(true) { return }
                socket.cancel(with: .goingAway, reason: nil)
                cont.resume(throwing: APIError(message: timeoutText))
            }
        }
    }

    private static func event(from message: URLSessionWebSocketTask.Message) -> RealtimeEvent {
        switch message {
        case .string(let s): return RealtimeEvent.parse(s)
        case .data(let d): return RealtimeEvent.parse(String(decoding: d, as: UTF8.self))
        @unknown default: return RealtimeEvent()
        }
    }
}
