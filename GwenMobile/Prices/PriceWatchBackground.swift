import GwenMobileKit
import Foundation

enum PriceWatchBackground {
    @MainActor
    static func register() { PriceWatchBackgroundPort.current.register() }

    @MainActor
    static func scheduleNext(store: PriceWatchStore = PriceWatchStore(), now: Date = Date()) async {
        await PriceWatchBackgroundPort.current.scheduleNext(store: store, now: now)
    }
}
