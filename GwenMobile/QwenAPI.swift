import Foundation

enum QwenAPI {
    static func makeRequest(baseURL: String, key: String, model: String,
                            messages: [ChatMessage], imageData: [Data],
                            stream: Bool = true, system: String? = nil,
                            thinking: ThinkingDirective = .nothing) throws -> URLRequest {
        let url = try HTTP.chatCompletionsURL(baseURL)
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": system ?? SystemPrompt.chat()],
        ] + zip(messages, contentParts(messages: messages, imageData: imageData)).map { m, c in
            ["role": m.role.rawValue, "content": c]
        }
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": stream,
        ]
        thinking.applied(to: &body)
        return try HTTP.jsonPOST(url: url, key: key, body: body,
                                 timeout: APITimeout.chatRequest, accept: "application/json")
    }

    static func dataURL(_ data: Data) -> String {
        "data:image/jpeg;base64,\(MediaStore.apiData(data).base64EncodedString())"
    }

    private static func contentParts(messages: [ChatMessage], imageData: [Data]) -> [Any] {
        var parts: [Any] = []
        var imgIdx = imageData.startIndex
        for m in messages {
            if m.role == .user, !m.images.isEmpty {
                var items: [[String: Any]] = [[
                    "type": "text",
                    "text": m.text.isEmpty ? L.t("describe_images") : m.text,
                ]]
                for _ in m.images {
                    if imgIdx < imageData.endIndex {
                        items.append([
                            "type": "image_url",
                            "image_url": ["url": dataURL(imageData[imgIdx])],
                        ])
                        imgIdx += 1
                    }
                }
                parts.append(items)
            } else {
                parts.append(m.text)
            }
        }
        return parts
    }

    static func askText(_ req: URLRequest) async throws -> String? {
        let data = try await HTTP.jsonData(req)
        return try await Offload.run {
            guard let obj = try? JSONDecoder().decode(ChatResponse.self, from: data) else { return nil }
            return obj.answerText
        }
    }

    static func resolveQuery(baseURL: String, key: String, model: String,
                             history: [ChatMessage],
                             thinking: ThinkingDirective = .nothing) async throws -> String? {
        guard let last = history.last?.text.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty else {
            return nil
        }
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: FollowUpResolver.requestMessages(text: last, history: history),
                                  imageData: [], stream: false, system: Prompt.Research.followUpQuery(),
                                  thinking: thinking)
        return try await askText(req)
    }

    static func composeImagePrompt(baseURL: String, key: String, model: String,
                                   instruction: String,
                                   history: [ChatMessage],
                                   pictures: Int = 1,
                                   thinking: ThinkingDirective = .nothing) async throws -> String? {
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: ImagePromptComposer.requestMessages(text: instruction, history: history),
                                  imageData: [], stream: false,
                                  system: Prompt.Research.imagePrompt(pictures: pictures),
                                  thinking: thinking)
        guard let raw = try await askText(req) else { return nil }
        return ImagePromptComposer.usablePrompt(raw, insteadOf: instruction)
    }

    static func fetchModelsRequest(baseURL: String, key: String) throws -> URLRequest {
        guard let url = HTTP.endpoint(baseURL, APIEndpoint.models) else {
            throw APIError(message: L.t("bad_url"))
        }
        return HTTP.authorizedGET(url: url, key: key, timeout: APITimeout.modelsRequest)
    }

    static func fetchModels(baseURL: String, key: String) async throws -> [String] {
        let req = try fetchModelsRequest(baseURL: baseURL, key: key)
        let (data, resp) = try await HTTP.data(req)
        try HTTP.ensureAPISuccess(resp, data: data)
        return try await Offload.run {
            try JSONDecoder().decode(ModelsPayload.self, from: data).data.map(\.id).sorted()
        }
    }

    static func makeImageRequest(baseURL: String, key: String, model: String,
                                 prompt: String, inputImages: [Data],
                                 isEdit: Bool = false) throws -> URLRequest {
        let url = try HTTP.chatCompletionsURL(baseURL)
        var parts: [[String: Any]] = []
        for data in inputImages {
            parts.append(["image": dataURL(data)])
        }
        let finalText: String
        if !isEdit || inputImages.isEmpty {
            finalText = prompt
        } else {
            finalText = L.fmt(inputImages.count == 1 ? "edit_frame" : "edit_frame_multi", prompt)
        }
        parts.append(["text": finalText])
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": parts]],
        ]
        return try HTTP.jsonPOST(url: url, key: key, body: body, timeout: APITimeout.imageRequest)
    }

    static func generateImage(req: URLRequest) async throws -> [URL] {
        let (data, resp) = try await HTTP.data(req)
        try HTTP.ensureAPISuccess(resp, data: data)
        let parsed = try await Offload.run { () -> (urls: [URL], note: String?) in
            guard let obj = try? JSONDecoder().decode(ChatResponse.self, from: data),
                  let content = obj.answerParts else {
                throw APIError(message: L.t("no_image"))
            }
            var urls: [URL] = []
            var note: String?
            for part in content {
                if let s = part.image, let u = URL(string: s) { urls.append(u) }
                if urls.isEmpty, let t = part.text, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    note = t
                }
            }
            return (urls, note)
        }
        guard !parsed.urls.isEmpty else { throw APIError(message: parsed.note ?? L.t("no_image")) }
        return parsed.urls
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, resp) = try await HTTP.data(URLRequest(url: url), using: URLSession.shared)
        try HTTP.ensureSuccess(resp)
        return data
    }

    static func detectImageIntent(baseURL: String, key: String, model: String,
                                  instruction: String,
                                  thinking: ThinkingDirective = .nothing) async -> ImageRoute? {
        let sys = Prompt.Router.imageIntent()
        let msg = ChatMessage(role: .user, text: instruction)
        guard let req = try? makeRequest(baseURL: baseURL, key: key, model: model,
                                         messages: [msg], imageData: [],
                                         stream: false, system: sys, thinking: thinking),
              let text = try? await askText(req) else { return nil }
        let t = text.lowercased()
        if t.contains("edit") { return .edit }
        if t.contains("create") { return .create }
        if t.contains("chat") { return .chat }
        return nil
    }

    struct CalendarPlan: Decodable {
        enum Action: String, Decodable { case create, update, delete, none }
        var action: Action
        var title: String?
        var start: String?
        var end: String?
        var location: String?
        var notes: String?
        var find: String?
        var alerts: [Int]?
        var calendar: String?
    }

    static func calendarPlan(baseURL: String, key: String, model: String,
                             instruction: String,
                             history: [ChatMessage] = [], events: String = "",
                             calendars: String = "",
                             thinking: ThinkingDirective = .nothing) async throws -> CalendarPlan? {
        let offset = TimeZone.current.secondsFromGMT()
        let oh = offset / 3600, om = abs(offset % 3600 / 60)
        let tz = String(format: "UTC%@%02d:%02d", offset < 0 ? "-" : "+", abs(oh), om)
        let sys = Prompt.Router.calendar(tz: tz, now: Formatters.planNow(Date()),
                                         events: events, calendars: calendars,
                                         history: ConversationTranscript.from(messages: history))
        let msg = ChatMessage(role: .user, text: instruction)
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: [msg], imageData: [], stream: false, system: sys,
                                  thinking: thinking)
        guard let raw = try await askText(req),
              let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}"),
              let json = raw[s...e].data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CalendarPlan.self, from: json) else { return nil }
        return CalendarPlanRefiner.refine(decoded, instruction: instruction)
    }

    private typealias Continuation = AsyncThrowingStream<String, Error>.Continuation

    private enum StreamOutcome {
        case finished
        case aborted
        case resetBeforeFirstByte(String)
        case failed(APIError)
    }

    static func streamText(req: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var retries = 0
                while true {
                    switch await streamPass(req: req, into: continuation) {
                    case .finished:
                        continuation.finish()
                        return
                    case .aborted:
                        continuation.finish(throwing: nil)
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
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func streamPass(req: URLRequest, into continuation: Continuation) async -> StreamOutcome {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await HTTP.session.bytes(for: req)
        } catch {
            return outcome(of: error, sawData: false)
        }
        var sawData = false
        do {
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                var body = ""
                for try await line in bytes.lines {
                    body += line
                    if body.count > 2000 { break }
                }
                throw APIError(message: APIErrorParser.message(from: body, status: http.statusCode),
                               status: http.statusCode)
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                sawData = true
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8) else { continue }
                if let obj = try? JSONDecoder().decode(ChatResponse.self, from: data),
                   let delta = obj.streamChunk, !delta.isEmpty {
                    continuation.yield(delta)
                }
            }
            guard sawData else { throw APIError(message: L.t("no_sse")) }
            return .finished
        } catch {
            return outcome(of: error, sawData: sawData)
        }
    }

    static func streamReset(of error: Error, sawData: Bool) -> Bool {
        guard !sawData, let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled && HTTP.isConnectionReset(urlError)
    }

    private static func outcome(of error: Error, sawData: Bool) -> StreamOutcome {
        if error is CancellationError { return .aborted }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .finished }
            if streamReset(of: error, sawData: sawData) {
                return .resetBeforeFirstByte(urlError.localizedDescription)
            }
        }
        if let apiError = error as? APIError { return .failed(apiError) }
        return .failed(APIError(message: error.localizedDescription))
    }
}

private struct ModelsPayload: Decodable {
    struct ModelEntry: Decodable { var id: String }
    var data: [ModelEntry]
}
