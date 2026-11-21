import GwenMobileKit
import Foundation

final class AudioLevelMeter: @unchecked Sendable {
    static let window: TimeInterval = 10
    static let floor = -120

    private let lock = NSLock()
    private let report: @Sendable (Int) -> Void
    private var loudest: Float = 0
    private var since: Date?

    init(report: @escaping @Sendable (Int) -> Void = { flowMark("MIKRO pegel spitze_db=\($0)") }) {
        self.report = report
    }

    func measure(peak: Float, at now: Date = Date()) {
        lock.lock()
        loudest = max(loudest, peak)
        let begun = since ?? now
        since = begun
        let due = now.timeIntervalSince(begun) >= Self.window
        let value = loudest
        if due {
            loudest = 0
            since = now
        }
        lock.unlock()
        if due { report(Self.decibels(value)) }
    }

    static func decibels(_ peak: Float) -> Int {
        guard peak > 0 else { return floor }
        return max(floor, Int((20 * log10(Double(peak))).rounded()))
    }
}
