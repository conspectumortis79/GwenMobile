import GwenMobileKit
import Foundation
import os

#if DEBUG
final class MonotonicCounter: Sendable {
    private let value = LockedValue(0)

    init(_ initial: Int = 0) { value.set(initial) }

    @discardableResult
    func bump() -> Int {
        value.mutate { current in
            current += 1
            return current
        }
    }

    var current: Int { value.current }
}

enum RenderStats {
    static let beats = MonotonicCounter()
    static let beatAt = LockedValue(ContinuousClock.now)
    static let chatBody = MonotonicCounter()
    static let bubbleBody = MonotonicCounter()
    static let attachmentBody = MonotonicCounter()
    static let attachmentTask = MonotonicCounter()
    static let ratioReads = MonotonicCounter()
    static let imageDecodes = MonotonicCounter()
    static let appends = MonotonicCounter()

    static func fields() -> String {
        "chat=\(chatBody.current) bubble=\(bubbleBody.current) att=\(attachmentBody.current) "
            + "task=\(attachmentTask.current) ratio=\(ratioReads.current) decode=\(imageDecodes.current) "
            + "append=\(appends.current) beats=\(beats.current)"
    }

    static func beat() {
        beats.bump()
        beatAt.set(ContinuousClock.now)
    }
}

enum StallProbe {
    static let pollIntervalMS = 200
    static let reportIntervalMS = 500
    static let statsIntervalMS = 2000

    static func start(thresholdMS: Int) {
        Task.detached(priority: .utility) {
            var lastBeatAt = RenderStats.beatAt.current
            var lastReport = ContinuousClock.now
            var lastStats = ContinuousClock.now
            var reported = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(pollIntervalMS))
                let beatAt = RenderStats.beatAt.current
                let now = ContinuousClock.now
                if beatAt > lastBeatAt {
                    let gap = msOf(lastBeatAt.duration(to: beatAt))
                    if reported, gap >= thresholdMS {
                        TraceSink.shared.append("STALL_END gap_ms=\(gap) \(RenderStats.fields())")
                    }
                    lastBeatAt = beatAt
                    reported = false
                }
                let since = msOf(lastBeatAt.duration(to: now))
                if since >= thresholdMS, !reported || msOf(lastReport.duration(to: now)) >= reportIntervalMS {
                    reported = true
                    lastReport = now
                    TraceSink.shared.append("STALL gap_ms=\(since) \(RenderStats.fields())")
                }
                if msOf(lastStats.duration(to: now)) >= statsIntervalMS {
                    lastStats = now
                    TraceSink.shared.append("STATS \(RenderStats.fields())")
                }
            }
        }
    }
}
#endif

@MainActor
enum MainLoopMonitor {
    static let interval = Duration.milliseconds(250)
    static let stallThresholdMS = 400
    private static let started = LockedValue(false)

    static func start() {
        #if DEBUG
        guard started.exchange(true) == false else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in RenderStats.beat() }
        RunLoop.main.add(timer, forMode: .common)
        StallProbe.start(thresholdMS: stallThresholdMS)
        Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let gap = msOf(last.duration(to: .now))
                last = .now
                RenderStats.beat()
                if gap > stallThresholdMS {
                    flowLog.error("MAINSTALL gap_ms=\(gap)")
                    TraceSink.shared.append("MAINSTALL gap_ms=\(gap) \(RenderStats.fields())")
                }
            }
        }
        #endif
    }
}
