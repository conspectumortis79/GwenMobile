#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
final class SweepReport {
    private let file: String
    private var lines: [String] = []

    init(file: String) {
        self.file = file
    }

    var content: String {
        lines.joined(separator: "\n")
    }

    func add(_ section: String, _ detail: String) {
        record("\(section): \(detail)")
    }

    func addFailure(_ section: String, _ error: Error) {
        let ns = error as NSError
        let host = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? (ns.userInfo[NSURLErrorFailingURLErrorKey].map { String(describing: $0) } ?? "-")
        record("\(section): FEHLER domain=\(ns.domain) code=\(ns.code) url=\(host.prefix(70)) "
               + "text=\(error.localizedDescription.prefix(320))")
    }

    private func record(_ line: String) {
        lines.append(line)
        flowLog.info("BERICHT \(self.file, privacy: .public) \(line, privacy: .public)")
        let url = StoragePaths().documents.appendingPathComponent(file)
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }
}
#endif
