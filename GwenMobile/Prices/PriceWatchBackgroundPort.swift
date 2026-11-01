import BackgroundTasks
import Foundation

@MainActor
protocol PriceWatchBackgroundScheduling {
    func register()
    func scheduleNext(store: PriceWatchStore, now: Date) async
    func handle(_ task: BGAppRefreshTask?) async
}

@MainActor
final class StubPriceWatchBackground: PriceWatchBackgroundScheduling {
    func register() {}
    func scheduleNext(store: PriceWatchStore, now: Date) async {}
    func handle(_ task: BGAppRefreshTask?) async {}
}

@MainActor
enum PriceWatchBackgroundPort {
    nonisolated(unsafe) static var current: any PriceWatchBackgroundScheduling = StubPriceWatchBackground()
}
