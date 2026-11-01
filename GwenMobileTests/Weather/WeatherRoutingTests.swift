@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WeatherRoutingTests: GwenTestCase {
    func testTheWeatherToolIsOffered() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.weatherTool))
    }

    func testTheWeatherToolNamesUmbrellaAndSunProtection() throws {
        let tool = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.weatherTool
        }
        let function = try XCTUnwrap(tool?["function"] as? [String: Any])
        let description = try XCTUnwrap(function["description"] as? String)
        XCTAssertTrue(description.contains("umbrella"))
        XCTAssertTrue(description.contains("sun protection"))
        XCTAssertTrue(description.contains("never invent"))
        XCTAssertTrue(description.contains("Never use it for news"), description)
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["place"])
        XCTAssertNotNil(properties["day"])
        XCTAssertNotNil(properties["date"])
        let date = (properties["date"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(date?.contains("12 October") ?? false, date ?? "")
        XCTAssertTrue(date?.contains("YYYY-MM-DD") ?? false, date ?? "")
        let offset = (properties["dayOffset"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(offset?.contains("3 the day after the day after tomorrow") ?? false, offset ?? "")
        XCTAssertTrue(offset?.contains("in four days") ?? false, offset ?? "")
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains("the day after the day after tomorrow 3"), block)
        XCTAssertTrue(block.contains("dayOffset"), block)
    }

    func testTheWeatherCallMapsOntoTheWeatherRoute() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.weatherTool, ["place": "München", "day": "dayAfter"])).first)
        guard case .weather(let request) = decision.route else {
            return XCTFail("tell_weather landete nicht im Wetter: \(decision.route)")
        }
        XCTAssertEqual(request.place, "München")
        XCTAssertEqual(request.day, .dayAfter)
        XCTAssertEqual(decision.stepKind, .weather)
    }

    func testAMissingPlaceStaysEmptyAndDefaultsToTomorrow() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.weatherTool, [:])).first)
        guard case .weather(let request) = decision.route else { return XCTFail("Wetter fehlt") }
        XCTAssertNil(request.place)
        XCTAssertEqual(request.day, .tomorrow)
        XCTAssertNil(request.date)
    }

    func testTheWeatherStepDoesNotMergeIntoAnotherAnswer() throws {
        let weather = try XCTUnwrap(ToolRouter.map(name: ToolRouter.weatherTool,
                                                   arguments: #"{"place":"Berlin","day":"today"}"#))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let plan = SendPlan.forming([weather, answer])
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertFalse(plan.merges)
    }

    func testTheSystemBlockNamesTheWeatherTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.weatherTool), block)
        XCTAssertTrue(block.contains("umbrella"), block)
        XCTAssertTrue(block.contains("Never use \(ToolRouter.weatherTool) for news"), block)
    }

    func testTheSearchToolOwnsNewsAsASingleWish() {
        let search = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.searchTool
        }
        let description = (search?["function"] as? [String: Any])?["description"] as? String ?? ""
        XCTAssertTrue(description.contains("only wish"), description)
        XCTAssertTrue(description.contains("news"), description)
    }

    func testTheTranscriptNeverDecidesTheTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(),
                                           transcript: "assistant: weather in Giengen")
        XCTAssertTrue(block.contains("background only"), block)
        XCTAssertTrue(block.contains("newest user message alone decides the tool"), block)
    }
}
