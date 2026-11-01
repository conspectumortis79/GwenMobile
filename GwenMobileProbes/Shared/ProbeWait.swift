#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum ProbeWait {
    @discardableResult
    static func until(_ seconds: Double, poll: Duration = .milliseconds(100),
                      _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return condition()
    }

    @discardableResult
    static func until(_ seconds: Int, poll: Duration = .milliseconds(100),
                      _ condition: @MainActor () -> Bool) async -> Bool {
        await until(Double(seconds), poll: poll, condition)
    }

    @discardableResult
    static func poll(_ seconds: Double, poll: Duration = .milliseconds(200),
                     _ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return await condition()
    }

    static func untilSettled(_ seconds: Double, stableRounds: Int = 2,
                             poll: Duration = .milliseconds(100),
                             _ value: @MainActor () -> Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        var last = value()
        var stable = 0
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: poll)
            let current = value()
            stable = current == last ? stable + 1 : 0
            if stable >= stableRounds { return true }
            last = current
        }
        return false
    }
}
#endif
