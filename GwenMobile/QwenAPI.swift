import Foundation

enum QwenAPI {
    static func makeRequest(baseURL: String, key: String, model: String,
                            messages: [ChatMessage], imageData: [Data],
                            stream: Bool = true, system: String? = nil,
                            thinking: ThinkingDirective = .nothing) throws -> URLRequest {
        guard let url = HTTP.endpoint(baseURL, APIEndpoint.chatCompletions) else {
            throw APIError(message: L.t("bad_url"))
        }
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
        guard let obj = try? JSONDecoder().decode(ChatResponse.self, from: data) else { return nil }
        return obj.answerText
    }

    static func resolveQuery(baseURL: String, key: String, model: String,
                             history: [ChatMessage],
                             thinking: ThinkingDirective = .nothing) async throws -> String? {
        guard let last = history.last?.text.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty else {
            return nil
        }
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: FollowUpResolver.requestMessages(text: last, history: history),
                                  imageData: [], stream: false, system: FollowUpResolver.instructions(),
                                  thinking: thinking)
        return try await askText(req)
    }

    static func composeImagePrompt(baseURL: String, key: String, model: String,
                                   instruction: String,
                                   history: [ChatMessage],
                                   thinking: ThinkingDirective = .nothing) async throws -> String? {
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: ImagePromptComposer.requestMessages(text: instruction, history: history),
                                  imageData: [], stream: false, system: ImagePromptComposer.instructions(),
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
        struct ModelsResp: Decodable {
            struct M: Decodable { var id: String }
            var data: [M]
        }
        return try JSONDecoder().decode(ModelsResp.self, from: data).data.map(\.id).sorted()
    }

    static func makeImageRequest(baseURL: String, key: String, model: String,
                                 prompt: String, inputImages: [Data],
                                 isEdit: Bool = false) throws -> URLRequest {
        guard let url = HTTP.endpoint(baseURL, APIEndpoint.chatCompletions) else {
            throw APIError(message: L.t("bad_url"))
        }
        var parts: [[String: Any]] = []
        for data in inputImages {
            parts.append(["image": dataURL(data)])
        }
        let finalText = (isEdit && !inputImages.isEmpty)
            ? L.t("edit_frame").replacingOccurrences(of: "%@", with: prompt)
            : prompt
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
        if urls.isEmpty { throw APIError(message: note ?? L.t("no_image")) }
        return urls
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, resp) = try await HTTP.data(URLRequest(url: url), using: URLSession.shared)
        try HTTP.ensureSuccess(resp)
        return data
    }

    static func detectImageIntent(baseURL: String, key: String, model: String,
                                  instruction: String,
                                  thinking: ThinkingDirective = .nothing) async -> ImageRoute? {
        let sys = """
        You are a router for an image tool. The user always attaches one or more existing images \
        plus a text instruction. Reply with exactly one word.
        EDIT — the instruction asks to modify the attached image itself: recoloring or repainting \
        an object, removing/adding/replacing something in the scene, changing the background, \
        style transfer, retouching, extending, fixing, annotating the same picture. \
        Examples: "make the mouse blue", "remove the watermark", "turn it into a cartoon", \
        "färbe die Maus blau", "hintergrund schwarz".
        CREATE — the instruction wants a brand-new picture that does not keep the attached image \
        as the scene, possibly only inspired by it. \
        Examples: "generate a wallpaper of a futuristic city", "draw a dragon like this one".
        CHAT — the instruction is a question or conversation about the image, or anything that \
        does not ask for a picture output. Examples: "what species is this?", "wer ist das?", \
        "schön, oder?".
        """
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
        let hist = ConversationTranscript.from(messages: history)
        var ctx = ""
        if !events.isEmpty {
            ctx += "\nExisting upcoming events (title \u{2014} start \u{2014} current notifications \u{2014} calendar):\n\(events)\n"
        }
        if !calendars.isEmpty {
            ctx += calendars
        }
        if !hist.isEmpty {
            ctx += "\nRecent conversation (use it to resolve what the user refers to):\n\(hist)\n"
        }
        let sys = """
        You are the calendar router of a chat app. Decide whether the user message asks to \
        create, change or delete a calendar appointment or reminder.
        Current local date & time: \(Formatters.planNow(Date())) (\(tz)). Times you output are local, 24h.\(ctx)
        Reply with ONLY one JSON object, no markdown fences:
        {"action":"create|update|delete|none","title":"...","start":"YYYY-MM-DD HH:MM",\
        "end":"YYYY-MM-DD HH:MM","location":"...","notes":"...","alerts":[60],\
        "calendar":"...","find":"words identifying the existing event"}
        Rules:
        - create: only for events NOT in the existing list above. "title" and "start" required; \
        if only a vague time is given use the next full hour; default "end" = start + 30 minutes; \
        omit fields the user did not mention.
        - "alerts": minutes before the start when the phone should REALLY notify the user \
        ("Hinweis 1 Stunde vorher" -> 60, "2ter Hinweis 2 Stunden vorher" -> also 120, "30 Min vorher" -> 30). \
        Include only when the user explicitly asks for a notification/reminder before the event; \
        NEVER put such timing into "notes" instead.
        - Adding, changing or removing a notification/Hinweis/Erinnerung for an event that already \
        exists (e.g. "Erinnere mich an X eine Stunde vorher", "füge noch einen zweiten Hinweis hinzu") \
        is ALWAYS action=update with "find" = that event's title and "alerts" = the FULL final list \
        (merge with the event's current notifications when adding; [] removes all). \
        NEVER create a duplicate event just to attach a reminder to it.
        - update: set "find" plus every changed field (new "start"/"end"/"title"/"location"). \
        Omit "alerts" to keep existing notifications.
        - "calendar": the exact title of the calendar the appointment belongs to. Set it whenever the user \
        names a calendar or describes one ("privat", "private", "persoenlich", "Arbeit", "work", "beruflich", \
        "Firma", "in meinem privaten Kalender"). Map the description onto one of the available calendar titles \
        when a list is given above, otherwise answer "privat" or "arbeit". On action=update this MOVES the \
        existing appointment to that calendar. Omit "calendar" when the user says nothing about it - the app \
        then files new appointments under the work calendar and keeps an existing appointment where it is.
        - A calendar wish NEVER belongs in "notes", "title" or "location": "privat", "nicht arbeit", \
        "private", "work", "privat statt arbeit" always goes into "calendar" only. Put text into "notes" \
        only when the user wants exactly that text stored inside the appointment.
        - A short follow-up that only names a calendar ("bitte privat statt arbeit", "mach das privat") is \
        action=update with "find" = the appointment from the recent conversation above and "calendar" set.
        - delete: set "find".
        - "none" for everything else, including questions about the calendar or standalone to-dos \
        that do not refer to an existing appointment.
        Resolve relative dates ("morgen", "uebermorgen", "naechsten Freitag", "in 2 Wochen", \
        "next Monday") against the current local date.
        """
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

    static func streamText(req: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await HTTP.session.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 2000 { break }
                        }
                        throw APIError(message: APIErrorParser.message(from: body, status: http.statusCode),
                                       status: http.statusCode)
                    }
                    var sawData = false
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
                    if !sawData {
                        throw APIError(message: L.t("no_sse"))
                    }
                    continuation.finish()
                } catch let e as APIError {
                    continuation.finish(throwing: e)
                } catch is CancellationError {
                    continuation.finish(throwing: nil)
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
