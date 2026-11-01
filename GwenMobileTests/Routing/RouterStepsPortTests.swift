@testable import GwenMobileFeatureCore
@testable import GwenMobileDevice
import GwenMobileKit
import XCTest

@MainActor
final class RouterStepsPortTests: GwenTestCase {
    func testTheStubRouterAnswersWithChat() async {
        RouterStepsPort.current = StubRouterSteps()
        defer { RouterStepsPort.current = SystemRouterSteps() }
        let ask = RouterAsk(baseURL: "https://example.test/v1", key: "k", model: "m", text: "Hallo",
                            context: SendContext(), history: [], thinking: .nothing)
        let decision = await ToolRouter.decide(ask)
        XCTAssertEqual(decision?.route, .chat)
        let steps = await ToolRouter.steps(ask)
        XCTAssertEqual(steps.map(\.route), [.chat])
        let plan = await ToolRouter.plan(ask)
        XCTAssertEqual(plan.actions.map(\.route), [.chat])
    }
}
