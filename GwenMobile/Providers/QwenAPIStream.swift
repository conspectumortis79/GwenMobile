import GwenMobileKit
import Foundation

extension QwenAPI {
    private typealias Continuation = AsyncThrowingStream<String, Error>.Continuation

    private enum StreamOutcome {
        case finished
        case cancelled
        case resetBeforeFirstByte(String)
        case rateLimited(APIError)
        case failed(APIError)
    }

    static let streamFlushInterval = Duration.milliseconds(50)
    static let streamFlushCharacters = 128

    nonisolated(unsafe) static var streamIdleOverride: TimeInterval?
    nonisolated(unsafe) static var localLines:
        (@Sendable (URLRequest) -> AsyncThrowingStream<String, Error>)?

    static func streamText(req: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var retries = 0
                var rateRetries = 0
                while true {
                    switch await streamPass(req: req, into: continuation) {
                    case .finished:
                        continuation.finish()
                        return
                    case .cancelled:
                        continuation.finish(throwing: CancellationError())
                        return
                    case .failed(let error):
                        continuation.finish(throwing: error)
                        return
                    case .resetBeforeFirstByte(let message):
                        guard retries == 0 else {
                            continuation.finish(throwing: APIError(message: message))
                            return
                        }
                        retries += 1
                        try? await Task.sleep(for: HTTP.connectionRetryBackoff)
                    case .rateLimited(let error):
                        guard rateRetries < 2 else {
                            continuation.finish(throwing: error)
                            return
                        }
                        rateRetries += 1
                        let wait = RateLimitRetry.backoff * rateRetries
                        flowMark("DROSSEL stream versuch=\(rateRetries) warte=\(wait)")
                        try? await Task.sleep(for: wait)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum ParsedLine: Equatable {
        case ignore(checkIdle: Bool)
        case done
        case payload(String)
    }

    private static func streamPass(req: URLRequest, into continuation: Continuation) async -> StreamOutcome {
        if LocalRuntime.isLocal(req) {
            return await consume(lines: Self.localLines?(req) ?? LocalRuntime.streamLines(req),
                                 into: continuation, parse: localLine)
        }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await HTTP.session.bytes(for: req)
        } catch {
            return outcome(of: error, sawData: false)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            do {
                var body = ""
                for try await line in bytes.lines {
                    body += line
                    if body.count > 2000 { break }
                }
                let error = APIError(message: APIErrorParser.message(from: body, status: http.statusCode),
                                     status: http.statusCode)
                if http.statusCode == 429 { return .rateLimited(error) }
                throw error
            } catch {
                return outcome(of: error, sawData: false)
            }
        }
        return await consume(lines: bytes.lines, into: continuation, parse: remoteLine)
    }

    private static func consume<Lines: AsyncSequence>(
        lines: Lines, into continuation: Continuation, parse: (String) -> ParsedLine
    ) async -> StreamOutcome where Lines.Element == String {
        var sawData = false
        var watch = StreamWatchdog(idle: Self.streamIdleOverride ?? APITimeout.streamIdle)
        let decoder = JSONDecoder()
        let pending = LockedValue("")
        func drain(force: Bool) {
            pending.mutate { buffer in
                guard force || buffer.count >= Self.streamFlushCharacters, !buffer.isEmpty else { return }
                let ready = buffer
                buffer = ""
                continuation.yield(ready)
            }
        }
        let flusher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.streamFlushInterval)
                drain(force: true)
            }
        }
        defer {
            flusher.cancel()
            drain(force: true)
        }
        do {
            var finished = false
            for try await line in lines {
                switch parse(line) {
                case .ignore(let checkIdle):
                    if checkIdle, watch.stalled { return stalled(watch) }
                case .done:
                    sawData = true
                    watch.noteContent()
                    finished = true
                case .payload(let payload):
                    sawData = true
                    watch.noteContent()
                    if let obj = try? decoder.decode(ChatResponse.self, from: Data(payload.utf8)),
                       let delta = obj.streamChunk, !delta.isEmpty {
                        pending.mutate { $0 += delta }
                        drain(force: false)
                    }
                }
                if finished { break }
            }
            guard sawData else { throw APIError(message: L.t("no_sse")) }
            return .finished
        } catch {
            return outcome(of: error, sawData: sawData)
        }
    }

    private static func remoteLine(_ line: String) -> ParsedLine {
        guard line.hasPrefix("data:") else { return .ignore(checkIdle: true) }
        let payload = line.dropFirst(5).drop(while: { $0 == " " || $0 == "\t" })
        if payload == "[DONE]" { return .done }
        return .payload(String(payload))
    }

    static func localLine(_ line: String) -> ParsedLine {
        guard line.hasPrefix("data:") else { return .ignore(checkIdle: true) }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return .ignore(checkIdle: false) }
        if payload == "[DONE]" { return .done }
        return .payload(payload)
    }

    static func streamReset(of error: Error, sawData: Bool) -> Bool {
        guard !sawData, let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled && HTTP.isConnectionReset(urlError)
    }

    private static func stalled(_ watch: StreamWatchdog) -> StreamOutcome {
        flowMark("STREAM gehalten seit \(Int(watch.idleFor))s ohne Datenzeile inhalt=\(watch.sawContent)")
        return watch.sawContent ? .finished : .failed(APIError(message: L.t("stream_stalled")))
    }

    private static func outcome(of error: Error, sawData: Bool) -> StreamOutcome {
        if error is CancellationError { return sawData ? .finished : .cancelled }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return sawData ? .finished : .cancelled }
            if streamReset(of: error, sawData: sawData) {
                return .resetBeforeFirstByte(urlError.localizedDescription)
            }
        }
        if let apiError = error as? APIError { return .failed(apiError) }
        return .failed(APIError(message: error.localizedDescription))
    }
}
