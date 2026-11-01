import Foundation
import os

public let flowLog = Logger(subsystem: "com.mortis.gwenmobile", category: "flow")

public func msOf(_ d: Duration) -> Int {
    let c = d.components
    return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
}

public func flowMark(_ text: String) {
    flowLog.info("\(text, privacy: .public)")
    if TraceSink.enabled { TraceSink.shared.mark(text) }
}

public func flowMarkPersonal(_ text: String) {
    flowLog.info("\(text, privacy: .private)")
    if TraceSink.enabled { TraceSink.shared.mark(text) }
}

public final class TraceSink: @unchecked Sendable {
    public static let traceKey = "gwenflowtrace"

    public static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: traceKey)
        #endif
    }

    public static let shared = TraceSink(url: StoragePaths().documents.appendingPathComponent("flow_trace.txt"))

    private let url: URL
    private let queue = DispatchQueue(label: "com.mortis.gwenmobile.trace")
    private var handle: FileHandle?

    public init(url: URL) {
        self.url = url
        queue.async { [url] in
            try? Data("==== trace start \(Date().timeIntervalSince1970)\n".utf8).write(to: url)
        }
    }

    public func mark(_ text: String) { append("MARK \(text)") }

    public func append(_ line: String) {
        let stamped = String(format: "%.3f ", Date().timeIntervalSince1970) + line + "\n"
        queue.async { [url] in
            #if DEBUG
            print(stamped, terminator: "")
            fflush(stdout)
            #endif
            guard let data = stamped.data(using: .utf8) else { return }
            if self.handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                self.handle = try? FileHandle(forWritingTo: url)
            }
            guard let handle = self.handle else {
                try? data.write(to: url)
                return
            }
            handle.seekToEndOfFile()
            handle.write(data)
        }
    }
}
