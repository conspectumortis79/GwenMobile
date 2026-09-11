import XCTest
@testable import GwenMobile

final class ChartPlanTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func decode(_ json: String) throws -> ChartPlan {
        try XCTUnwrap(ChartPlanner.plan(from: json))
    }

    func testFullPointArrayPlanIsDecoded() throws {
        let plan = try decode("""
        {"kind":"line","title":"Einwohnerentwicklung","unit":"Mio.","series":"Einwohner",
         "points":[{"label":"2020","value":83.2},{"label":"2024","value":84.7}]}
        """)
        XCTAssertEqual(plan.kind, .line)
        XCTAssertEqual(plan.title, "Einwohnerentwicklung")
        XCTAssertEqual(plan.unit, "Mio.")
        XCTAssertEqual(plan.series, "Einwohner")
        XCTAssertEqual(plan.points, [ChartPoint(label: "2020", value: 83.2),
                                     ChartPoint(label: "2024", value: 84.7)])
        XCTAssertTrue(plan.isUsable)
    }

    func testParallelArraysAndNumericLabelsAreAccepted() throws {
        let plan = try decode("""
        {"type":"Balkendiagramm","labels":[2021,2022,2023],"values":["12,5",8,"3,25"]}
        """)
        XCTAssertEqual(plan.kind, .bar)
        XCTAssertEqual(plan.points.map(\.label), ["2021", "2022", "2023"])
        XCTAssertEqual(plan.points.map(\.value), [12.5, 8, 3.25])
    }

    func testAlternateKeysAndBrokenPointsSurvive() throws {
        let plan = try decode("""
        {"caption":"Anteile","seriesName":"Marktabsatz","unit":"%","kind":"pie",
         "points":[{"category":"Nord","value":"31,4"},{"name":"Süd","value":"kaputt"},
                   {"label":"Ost","value":22.1},{"label":" ","value":9}]}
        """)
        XCTAssertEqual(plan.title, "Anteile")
        XCTAssertEqual(plan.series, "Marktabsatz")
        XCTAssertEqual(plan.kind, .pie)
        XCTAssertEqual(plan.points, [ChartPoint(label: "Nord", value: 31.4),
                                     ChartPoint(label: "Ost", value: 22.1)])
    }

    func testSinglePointPlanIsNotUsable() throws {
        XCTAssertNil(ChartPlanner.plan(from: #"{"kind":"bar","points":[{"label":"a","value":1}]}"#))
        XCTAssertNil(ChartPlanner.plan(from: #"{"kind":"bar","points":[]}"#))
    }

    func testGarbageOrFencedJsonIsHandled() {
        XCTAssertNil(ChartPlanner.plan(from: nil))
        XCTAssertNil(ChartPlanner.plan(from: ""))
        XCTAssertNil(ChartPlanner.plan(from: "ich kann das nicht"))
        XCTAssertNil(ChartPlanner.plan(from: "{ unvollständig"))
        XCTAssertNil(ChartPlanner.plan(from: "{"))
        let fenced = ChartPlanner.plan(from: """
        ```json
        {"kind":"bar","points":[{"label":"A","value":1},{"label":"B","value":2}]}
        ```
        """)
        XCTAssertEqual(fenced?.points.count, 2)
    }

    func testNumberParsingHandlesRealWorldShapes() {
        let valid: [(String, Double)] = [("12.5", 12.5), ("12,5", 12.5), ("1.234,56", 1234.56),
                                         ("1,234.56", 1234.56), ("12,345", 12345), ("-3,5", -3.5),
                                         ("\u{2212}7", -7), ("42 %", 42), ("  99  ", 99),
                                         ("1e3", 1000), ("0,5", 0.5), ("8,4", 8.4), ("7", 7)]
        for (raw, expected) in valid {
            XCTAssertEqual(ChartPlan.number(from: raw), expected, raw)
        }
        for junk in ["", "   ", "keine zahl", "1.2.3", "nan", "inf", "8,4 Mio", "%", ","] {
            XCTAssertNil(ChartPlan.number(from: junk), junk)
        }
    }

    func testCompactAndLocalisedNumbers() {
        XCTAssertEqual(ChartPlan.compact(1500), "1500")
        XCTAssertEqual(ChartPlan.compact(12.5), "12.5")
        XCTAssertEqual(ChartPlan.compact(0.25), "0.25")
        XCTAssertEqual(ChartPlan.compact(-3), "-3")
        XCTAssertEqual(ChartPlan.numberText(1234.5, locale: Locale(identifier: "de_DE")), "1.234,5")
        XCTAssertEqual(ChartPlan.numberText(1234.5, locale: Locale(identifier: "en_US")), "1,234.5")
    }

    func testImagePromptCarriesEveryValueAndLabel() throws {
        let plan = ChartPlan(kind: .bar, title: "Umsatz je Quartal", unit: "Mio. €",
                             series: "Netto", points: [ChartPoint(label: "Q1", value: 12.5),
                                                       ChartPoint(label: "Q2", value: 8),
                                                       ChartPoint(label: "Q3", value: 1234.56)])
        let prompt = plan.imagePrompt()
        XCTAssertTrue(prompt.contains("clean bar chart"))
        XCTAssertTrue(prompt.contains("Title: Umsatz je Quartal"))
        XCTAssertTrue(prompt.contains("Data series: Netto"))
        XCTAssertTrue(prompt.contains("values in Mio. € on the vertical axis"))
        XCTAssertTrue(prompt.contains("exactly these 3 values"))
        XCTAssertTrue(prompt.contains("Q1: 12.5"))
        XCTAssertTrue(prompt.contains("Q2: 8"))
        XCTAssertTrue(prompt.contains("Q3: 1234.56"))
        XCTAssertTrue(prompt.contains("no watermark"))
    }

    func testSummaryListsDataWithSourceReferences() {
        let sources = [WebSource(title: "A", url: "https://a.test", domain: "a.test"),
                       WebSource(title: "B", url: "https://b.test", domain: "b.test")]
        let summary = ChartPlan(kind: .pie, title: "Anteile", unit: "%",
                                points: [ChartPoint(label: "Nord", value: 31.4),
                                         ChartPoint(label: "Süd", value: 8)])
            .summary(sources: sources, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(summary, "**Anteile**\n\n- Nord: 31,4 %\n- Süd: 8 %\n\nDaten: [1] [2]")
    }

    func testSummaryWithoutSourcesOrTitleStillShowsTheValues() {
        let summary = ChartPlan(points: [ChartPoint(label: "2020", value: 83.2)])
            .summary(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(summary, "- 2020: 83.2")
    }

    func testRequestCarriesQuestionAndDataBlock() throws {
        let req = try ChartPlanner.makeRequest(baseURL: "https://api.test/v1", key: "sk-t", model: "qwen-x",
                                               question: "Anteile bitte als diagramm", data: "TEXT 31,4 %")
        XCTAssertEqual(req.url?.absoluteString, "https://api.test/v1/chat/completions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen-x")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(user.contains("## DATA"))
        XCTAssertTrue(user.contains("TEXT 31,4 %"))
        XCTAssertTrue(user.contains("Anteile bitte als diagramm"))
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("ONLY one JSON object"))
        XCTAssertTrue(system.contains("\"points\""))
    }

    func testRequestWithoutDataKeepsOnlyTheQuestion() throws {
        let req = try ChartPlanner.makeRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                              question: "nur frage", data: "")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertFalse(user.contains("## DATA"))
        XCTAssertTrue(user.contains("nur frage"))
    }
}
