import Foundation

struct ChartPoint: Equatable, Sendable {
    var label: String
    var value: Double
}

struct ChartPlan: Decodable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case bar, line, pie, area, scatter

        static func recognised(_ raw: String) -> Kind {
            let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = Kind(rawValue: t) { return exact }
            if t.contains("area") || t.contains("fläch") || t.contains("flaeche") { return .area }
            if t.contains("pie") || t.contains("kreis") || t.contains("kuchen") || t.contains("donut") { return .pie }
            if t.contains("line") || t.contains("kurve") || t.contains("trend") || t.contains("zeit") { return .line }
            if t.contains("scatter") || t.contains("punkt") { return .scatter }
            return .bar
        }
    }

    var kind: Kind = .bar
    var title: String = ""
    var unit: String = ""
    var series: String = ""
    var points: [ChartPoint] = []

    init(kind: Kind = .bar, title: String = "", unit: String = "", series: String = "",
         points: [ChartPoint] = []) {
        self.kind = kind
        self.title = title
        self.unit = unit
        self.series = series
        self.points = points
    }

    var isUsable: Bool { points.count >= 2 }

    init(from decoder: Decoder) throws {
        let payload = try? Payload(from: decoder)
        kind = Kind.recognised(payload?.kind ?? payload?.type ?? "")
        title = Self.trimmed(payload?.title ?? payload?.caption)
        unit = Self.trimmed(payload?.unit)
        series = Self.trimmed(payload?.series ?? payload?.seriesName)
        points = Self.points(from: payload?.points, labels: payload?.labels, values: payload?.values)
    }

    func imagePrompt() -> String {
        var lines = ["Draw a clean \(kind.rawValue) chart of the data below. This is a factual data graphic, "
                     + "not an illustration."]
        if !title.isEmpty { lines.append("Title: \(title)") }
        if !series.isEmpty { lines.append("Data series: \(series)") }
        lines.append(unit.isEmpty
                     ? "Axes: categories on the horizontal axis, values on the vertical axis."
                     : "Axes: categories on the horizontal axis, values in \(unit) on the vertical axis.")
        lines.append("Plot exactly these \(points.count) values, each bar or point in correct proportion to the others:")
        lines += points.map { "\($0.label): \(Self.compact($0.value))" }
        lines.append("Write every label and every number legibly and with correct spelling, "
                     + "no invented words, no watermark, no logo.")
        lines.append("Style: flat vector infographic, white background, distinct colors, thin gridlines, no 3D, no shadow.")
        return lines.joined(separator: "\n")
    }

    func summary(sources: [WebSource] = [], locale: Locale = L.lang.locale) -> String {
        var blocks: [String] = []
        if !title.isEmpty { blocks.append("**\(title)**") }
        let suffix = unit.isEmpty ? "" : " \(unit)"
        blocks.append(points.map { "- \($0.label): \(Self.numberText($0.value, locale: locale))\(suffix)" }
                          .joined(separator: "\n"))
        if !sources.isEmpty {
            let refs = sources.indices.map { "[\($0 + 1)]" }.joined(separator: " ")
            blocks.append("\(L.t("chart_data_line")) \(refs)")
        }
        return blocks.joined(separator: "\n\n")
    }

    static func compact(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(format: "%.0f", value) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func numberText(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? compact(value)
    }

    static func number(from raw: String) -> Double? {
        var text = raw
        for junk in ["\u{00a0}", " ", "%", "€", "$", "USD", "EUR"] {
            text = text.replacingOccurrences(of: junk, with: "")
        }
        text = text.replacingOccurrences(of: "−", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains(","), text.contains(".") {
            let commaIsLast = (text.lastIndex(of: ",") ?? text.startIndex) > (text.lastIndex(of: ".") ?? text.startIndex)
            text = commaIsLast ? text.replacingOccurrences(of: ".", with: "")
                               : text.replacingOccurrences(of: ",", with: "")
        }
        let parts = text.split(separator: ",")
        let grouped = parts.count == 2 && parts[1].count == 3 && !parts[0].isEmpty
        text = grouped ? text.replacingOccurrences(of: ",", with: "")
                       : text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text) else { return nil }
        return value.isFinite ? value : nil
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func points(from payloads: [PointPayload]?, labels: [LooseNumber]?,
                               values: [LooseNumber]?) -> [ChartPoint] {
        if let payloads {
            return payloads.compactMap { payload in
                let label = Self.trimmed(payload.label ?? payload.category ?? payload.x?.label)
                guard let value = (payload.value ?? payload.y)?.number, !label.isEmpty else { return nil }
                return ChartPoint(label: label, value: value)
            }
        }
        guard let labels, let values else { return [] }
        return zip(labels, values).compactMap { label, number in
            let text = Self.trimmed(label.label)
            guard let value = number.number, !text.isEmpty else { return nil }
            return ChartPoint(label: text, value: value)
        }
    }
}

private struct LooseNumber: Decodable {
    var number: Double?
    var label: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            number = value.isFinite ? value : nil
            label = value.isFinite ? ChartPlan.compact(value) : nil
            return
        }
        if let value = try? container.decode(Int.self) {
            number = Double(value)
            label = String(value)
            return
        }
        if let flag = try? container.decode(Bool.self) {
            number = flag ? 1 : 0
            label = flag ? "1" : "0"
            return
        }
        let text = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines)
        number = text.flatMap { ChartPlan.number(from: $0) }
        label = text?.nilIfEmpty
    }
}

private struct PointPayload: Decodable {
    var label: String?
    var category: String?
    var x: LooseNumber?
    var value: LooseNumber?
    var y: LooseNumber?
}

private struct Payload: Decodable {
    var kind: String?
    var type: String?
    var title: String?
    var caption: String?
    var unit: String?
    var series: String?
    var seriesName: String?
    var points: [PointPayload]?
    var labels: [LooseNumber]?
    var values: [LooseNumber]?
}
