#if DEBUG
import UIKit

final class ShareProbeEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ text: String) {
        lock.lock()
        lines.append(text)
        lock.unlock()
        flowMark("SHAREPROBE \(text)")
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

@MainActor
final class ShareFlowObserver {
    private struct Snapshot: Equatable {
        var kette = "-"
        var sheetImFenster = false
        var sheetSichtbar = false
        var sheetVerschachtelt = "-"
    }

    private let sheet: UIActivityViewController
    private let events: ShareProbeEvents
    private let started = ContinuousClock.now
    private var last = Snapshot()

    init(sheet: UIActivityViewController, events: ShareProbeEvents) {
        self.sheet = sheet
        self.events = events
        observeCallbacks(of: sheet)
    }

    func tick() {
        let now = read()
        if now != last {
            events.add(String(format: "t=%.1f ", stamp()) + "ZUSTAND imFenster=\(now.sheetImFenster) "
                       + "sichtbar=\(now.sheetSichtbar) verschachtelt=\(now.sheetVerschachtelt) kette=\(now.kette)")
            last = now
        }
    }

    var sheetIsGone: Bool {
        let now = read()
        return !now.sheetImFenster && !now.sheetSichtbar
    }

    private func stamp() -> Double {
        Double(started.duration(to: .now).components.seconds)
    }

    private func observeCallbacks(of sheet: UIActivityViewController) {
        let inner = sheet.completionWithItemsHandler
        let events = self.events
        let started = self.started
        sheet.completionWithItemsHandler = { typ, fertig, items, fehler in
            let t = Double(started.duration(to: .now).components.seconds)
            events.add(String(format: "t=%.1f ", t) + "CALLBACK typ=\(typ?.rawValue ?? "nil") fertig=\(fertig) "
                       + "items=\(items.map { $0.count } ?? -1) "
                       + "fehler=\(fehler.map { String($0.localizedDescription.prefix(60)) } ?? "nil")")
            inner?(typ, fertig, items, fehler)
        }
    }

    private func read() -> Snapshot {
        var s = Snapshot()
        s.sheetImFenster = sheet.presentingViewController != nil
        s.sheetSichtbar = sheet.viewIfLoaded?.window != nil
        s.sheetVerschachtelt = sheet.presentedViewController.map { String(describing: type(of: $0)) } ?? "keine"
        s.kette = Self.chain(from: Presenter.windowRootViewController)
        return s
    }

    static func chain(from root: UIViewController?) -> String {
        guard let root else { return "-" }
        var names = [String(describing: type(of: root))]
        var top = root
        while let next = top.presentedViewController {
            names.append(String(describing: type(of: next)))
            top = next
        }
        return names.joined(separator: ">")
    }
}
#endif
