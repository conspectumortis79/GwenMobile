import Foundation
import os

let flowLog = Logger(subsystem: "com.mortis.gwenmobile", category: "flow")

func msOf(_ d: Duration) -> Int {
    let c = d.components
    return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
}

func flowMark(_ text: String) {
    flowLog.info("\(text, privacy: .public)")
    #if DEBUG
    TraceSink.shared.mark(text)
    #endif
}

#if DEBUG
final class MonotonicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    init(_ initial: Int = 0) { value = initial }

    @discardableResult
    func bump() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum RenderStats {
    static let beats = MonotonicCounter()
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
}

final class TraceSink: @unchecked Sendable {
    static let shared = TraceSink(url: StoragePaths().documents.appendingPathComponent("flow_trace.txt"))

    private let url: URL
    private let queue = DispatchQueue(label: "com.mortis.gwenmobile.trace")

    init(url: URL) {
        self.url = url
        queue.async { [url] in
            try? "==== trace start \(Date().timeIntervalSince1970)\n".data(using: .utf8)?.write(to: url)
        }
    }

    func mark(_ text: String) { append("MARK \(text)") }

    func append(_ line: String) {
        let stamped = String(format: "%.3f ", Date().timeIntervalSince1970) + line + "\n"
        queue.async { [url] in
            guard let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

enum StallProbe {
    static let pollIntervalMS = 200
    static let reportIntervalMS = 500
    static let statsIntervalMS = 2000

    static func start(thresholdMS: Int) {
        Task.detached(priority: .utility) {
            var lastBeat = RenderStats.beats.current
            var lastChange = ContinuousClock.now
            var lastReport = ContinuousClock.now
            var lastStats = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(pollIntervalMS))
                let beat = RenderStats.beats.current
                let now = ContinuousClock.now
                let gap = msOf(lastChange.duration(to: now))
                if beat != lastBeat {
                    if gap >= thresholdMS {
                        TraceSink.shared.append("STALL_END gap_ms=\(gap) \(RenderStats.fields())")
                    }
                    lastBeat = beat
                    lastChange = now
                }
                if gap >= thresholdMS, msOf(lastReport.duration(to: now)) >= reportIntervalMS {
                    lastReport = now
                    TraceSink.shared.append("STALL gap_ms=\(gap) \(RenderStats.fields())")
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
    nonisolated(unsafe) static var running = false
    #if DEBUG
    nonisolated(unsafe) static var heartbeatTimer: Timer?
    #endif

    static func start() {
        guard !running else { return }
        running = true
        #if DEBUG
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in RenderStats.beats.bump() }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
        StallProbe.start(thresholdMS: stallThresholdMS)
        #endif
        Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let gap = msOf(last.duration(to: .now))
                last = .now
                #if DEBUG
                RenderStats.beats.bump()
                #endif
                if gap > stallThresholdMS {
                    flowLog.error("MAINSTALL gap_ms=\(gap)")
                }
            }
        }
    }
}
