import Foundation

@MainActor
protocol RouterStepPlanning: Sendable {
    func steps(_ ask: RouterAsk) async -> [ToolDecision]
}

@MainActor
struct StubRouterSteps: RouterStepPlanning {
    func steps(_ ask: RouterAsk) async -> [ToolDecision] { [ToolDecision(route: .chat)] }
}

@MainActor
enum RouterStepsPort {
    nonisolated(unsafe) static var current: any RouterStepPlanning = StubRouterSteps()
}
