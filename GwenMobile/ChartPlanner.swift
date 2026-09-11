import Foundation

enum ChartPlanner {
    static let maxDataChars = 9000

    static func makeRequest(baseURL: String, key: String, model: String,
                           question: String, data: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": instructions()],
                ["role": "user", "content": userContent(question: question, data: data)],
            ],
        ]
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                timeout: APITimeout.chatRequest)
    }

    static func userContent(question: String, data: String) -> String {
        data.isEmpty ? "## Frage\n\(question)" : "## DATA\n\(data)\n\n## Frage\n\(question)"
    }

    static func plan(from raw: String?) -> ChartPlan? {
        guard let raw, let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let json = String(raw[start...end]).data(using: .utf8),
              let plan = try? JSONDecoder().decode(ChartPlan.self, from: json) else { return nil }
        return plan.isUsable ? plan : nil
    }

    static func plan(baseURL: String, key: String, model: String,
                     question: String, data: String) async throws -> ChartPlan? {
        let capped = data.count > maxDataChars ? String(data.prefix(maxDataChars)) : data
        let raw = try await QwenAPI.askText(makeRequest(baseURL: baseURL, key: key, model: model,
                                                       question: question, data: capped))
        return plan(from: raw)
    }

    private static func instructions() -> String {
        """
        You are the chart planner of a chat app. Turn the request into ONE chart that an image model will draw.
        Reply with ONLY one JSON object, no markdown fences, no comments:
        {"kind":"bar|line|pie|area|scatter","title":"short title in the language of the request",\
        "unit":"unit of the values such as % or Mio. or kWh, empty when unitless",\
        "series":"short name of the data series",\
        "points":[{"label":"category, year or country","value":12.34}]}
        Rules:
        - Copy values ONLY from the DATA block. Never estimate, never round a different way, never add numbers \
        from your own knowledge while a DATA block is present.
        - If the DATA block is missing a number you need, leave that point out. If fewer than two numbers are \
        available, answer {"kind":"bar","points":[]}.
        - 2 to 8 points, in the order the data gives them (chronological for a time series).
        - kind: bar for comparisons, line or area for developments over time, pie for shares of one whole, \
        scatter for paired measurements.
        - "value" is a plain decimal number with a dot as the decimal sign, no thousands separator, no unit, \
        no quotes around it.
        - "label" is at most 24 characters, in the language of the request, and it must be readable inside a chart.
        - Only when there is NO DATA block at all you may use your own knowledge for the numbers.
        """
    }
}
