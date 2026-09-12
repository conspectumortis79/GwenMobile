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
                ["role": "system", "content": instructions(hasImages: !images.isEmpty)],
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

    private static func instructions(hasImages: Bool) -> String {
        var text = """
        You are the chart planner of a chat app. Turn the request into ONE chart that an image model will draw.
        Reply with ONLY one JSON object, no markdown fences, no comments:
        {"kind":"bar|line|pie|area|scatter","title":"short title in the language of the request",\
        "unit":"unit of the values such as % or Mio. or kWh, empty when unitless",\
        "series":"short name of the data series",\
        "points":[{"label":"category, year or country","value":12.34}]}
        Rules:
        - Copy values ONLY from the data you are given: the DATA block and, when one is attached, the picture.
        Never estimate, never round a different way, never add numbers from your own knowledge while data is \
        present.
        - If the DATA block is missing a number you need, leave that point out. If fewer than two numbers are \
        available, answer {"kind":"bar","points":[]}.
        - 2 to 8 points, in the order the data gives them (chronological for a time series). Prefer 4 to 8 \
        points whenever the data offers them: use every year or category that carries a number, never stop at \
        the first and the last value only.
        - kind: bar for comparisons, line or area for developments over time, pie for shares of one whole, \
        scatter for paired measurements.
        - "value" is a plain decimal number with a dot as the decimal sign, no thousands separator, no unit, \
        no quotes around it.
        - "label" is at most 24 characters, in the language of the request, and it must be readable inside a chart.
        - Only when there is NO DATA block at all you may use your own knowledge for the numbers.
        """
        guard hasImages else { return text }
        text += """

        A picture is attached to this request, so it counts as data: read its labels, dates and numbers with \
        your eyes and copy them exactly. Prefer the DATA block when it carries the needed numbers, use the \
        picture when the DATA block is missing or incomplete, and never fall back to your own knowledge while \
        a picture is attached. Never invent a value that is neither in the DATA block nor readable in the \
        picture.
        """
        return text
    }
}
