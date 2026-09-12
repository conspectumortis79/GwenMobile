import Foundation

enum ChartPlanner {
    static let maxDataChars = 9000
    static let maxInputImages = 2

    static func makeRequest(baseURL: String, key: String, model: String,
                            question: String, data: String, images: [Data] = [],
                            thinking: ThinkingDirective = .nothing) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": Prompt.Research.chartPlan(hasImages: !images.isEmpty)],
                ["role": "user", "content": userContent(question: question, data: data, images: images)],
            ],
        ]
        thinking.applied(to: &body)
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                timeout: APITimeout.chatRequest)
    }

    static func userContent(question: String, data: String, images: [Data] = []) -> Any {
        let text = data.isEmpty ? "## Frage\n\(question)" : "## DATA\n\(data)\n\n## Frage\n\(question)"
        guard !images.isEmpty else { return text }
        var parts: [[String: Any]] = [["type": "text", "text": text]]
        for image in images.prefix(maxInputImages) {
            parts.append(["type": "image_url", "image_url": ["url": QwenAPI.dataURL(image)]])
        }
        return parts
    }

    static func plan(from raw: String?) -> ChartPlan? {
        guard let raw, let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let json = String(raw[start...end]).data(using: .utf8),
              let plan = try? JSONDecoder().decode(ChartPlan.self, from: json) else { return nil }
        return plan.isUsable ? plan : nil
    }

    static func plan(baseURL: String, key: String, model: String, question: String, data: String,
                     images: [Data] = [],
                     thinking: ThinkingDirective = .nothing,
                     attempts: Int = 2) async throws -> ChartPlan? {
        let capped = data.count > maxDataChars ? String(data.prefix(maxDataChars)) : data
        for attempt in 1...max(1, attempts) {
            let raw = try await Offload.run { () -> String? in
                let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                          question: question, data: capped, images: images,
                                          thinking: thinking)
                return try await QwenAPI.askText(req)
            }
            if let plan = plan(from: raw) { return plan }
            flowMark("CHARTPLAN unbrauchbar versuch=\(attempt) daten=\(capped.count) "
                     + "bilder=\(images.count) antwort=\(oneLine(raw))")
        }
        return nil
    }

    private static func oneLine(_ raw: String?) -> String {
        String((raw ?? "keine Antwort").replacingOccurrences(of: "\n", with: " ").prefix(220))
    }

}
