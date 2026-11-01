@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugChipTapProbe {
    static let fitting = [
        WebSource(title: "Berlin", url: "https://www.berlin.de/aktuelles", domain: "www.berlin.de"),
        WebSource(title: "Hamburg", url: "https://www.hamburg.de/aktuelles", domain: "www.hamburg.de"),
    ]

    static let overflowing = [
        WebSource(title: "Closer", url: "https://www.closermag.fr/people/cannes-2025-natalie-portman", domain: "www.closermag.fr"),
        WebSource(title: "Hamburg", url: "https://yihf.chatradio-hamburg1.de/oscarorakel-heidi-tippt-auf-natalie-portman/",
                  domain: "yihf.chatradio-hamburg1.de"),
        WebSource(title: "Fity", url: "https://fity.club/lists/suggestions/natalie-portman-a-idade-profissional/",
                  domain: "fity.club"),
        WebSource(title: "Hawt", url: "https://www.hawtcelebs.com/natalie-portman-at-christian-dior-haute-couture-ss24-show-at-paris-fashion-week-01-22-2024/",
                  domain: "www.hawtcelebs.com"),
        WebSource(title: "Vogue", url: "https://www.vogue.fr/article/festival-de-cannes-2023-natalie-portman-dior-chopard-retour-sensation",
                  domain: "www.vogue.fr"),
        WebSource(title: "Starstyle", url: "http://www.starstyle.com/natalie-portman-december-premiere-sp684292/",
                  domain: "www.starstyle.com"),
    ]

    static func seed(_ view: ChatView) async {
        let report = SweepReport(file: "chip_tap.txt")
        view.store.newConversation()
        guard let id = view.store.currentID else {
            report.add("aufbau", "keine unterhaltung")
            return
        }
        view.store.appendMessage(ChatMessage(role: .user, text: "zwei quellen"), to: id)
        view.store.appendAssistant("Zwei Quellen [1] [2].", model: "probe", elapsed: 1, to: id, sources: fitting)
        view.store.appendMessage(ChatMessage(role: .user, text: "sechs quellen"), to: id)
        view.store.appendAssistant("Sechs Quellen [1] [2] [3] [4] [5] [6].", model: "probe", elapsed: 1, to: id,
                                   sources: overflowing)
        try? await Task.sleep(for: .seconds(2))
        guard let window = Presenter.windowRootViewController?.view?.window else {
            report.add("fenster", "keins")
            return
        }
        report.add("fenster", "breite=\(Int(window.bounds.width))")
        for (index, scroll) in ViewSearching.scrolls(in: window).enumerated() {
            let frame = scroll.convert(scroll.bounds, to: window)
            report.add("scroll\(index)", "typ=\(type(of: scroll)) frame=\(Int(frame.minX)),\(Int(frame.minY)),"
                       + "\(Int(frame.width))x\(Int(frame.height)) inhalt=\(Int(scroll.contentSize.width))x"
                       + "\(Int(scroll.contentSize.height)) delays=\(scroll.delaysContentTouches) "
                       + "cancels=\(scroll.canCancelContentTouches) "
                       + "erkenner=\((scroll.gestureRecognizers ?? []).map { String(describing: type(of: $0)) })")
        }
    }

    static func real(_ view: ChatView) async {
        let report = SweepReport(file: "chip_real.txt")
        let real = view.store.conversations.filter { conversation in
            !conversation.messages.contains { $0.model == "probe" }
        }
        guard let target = real.max(by: { sourceCount($0) < sourceCount($1) }) else {
            report.add("aufbau", "keine echte unterhaltung")
            return
        }
        view.store.currentID = target.id
        report.add("unterhaltung", "nachrichten=\(target.messages.count) mit_quellen=\(sourceCount(target)) "
                   + "letzte_quellen=\(target.messages.last?.sources?.count ?? 0) "
                   + "letzte_galerie=\(target.messages.last?.gallery?.pictures.count ?? 0)")
        try? await Task.sleep(for: .seconds(3))
        guard let window = Presenter.windowRootViewController?.view?.window else { return }
        for (index, scroll) in ViewSearching.scrolls(in: window).enumerated() where !(scroll is UITextView) {
            let frame = scroll.convert(scroll.bounds, to: window)
            report.add("scroll\(index)", "frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x"
                       + "\(Int(frame.height)) inhalt=\(Int(scroll.contentSize.width))x\(Int(scroll.contentSize.height)) "
                       + "offset=\(Int(scroll.contentOffset.x)),\(Int(scroll.contentOffset.y))")
        }
    }

    static func touch(_ view: ChatView) async {
        ChipTouchLog.install()
        await real(view)
    }

    private static func sourceCount(_ conversation: Conversation) -> Int {
        conversation.messages.filter { !($0.sources ?? []).isEmpty }.count
    }
}

@MainActor
enum ChipTouchLog {
    private struct Start {
        let point: CGPoint
        let time: TimeInterval
        var farthest: CGFloat
    }

    private static var installed = false
    private static var starts: [ObjectIdentifier: Start] = [:]
    private static var notificationTokens: [NSObjectProtocol] = []

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let logging = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.chipProbeSendEvent(_:)))
        else { return }
        installed = true
        method_exchangeImplementations(original, logging)
        let names = [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification]
        for name in names {
            notificationTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { note in
                    flowMark("CHIPAPP \(note.name.rawValue)")
                })
        }
        flowMark("CHIPTOUCH installiert")
    }

    static func record(_ event: UIEvent) {
        guard event.type == .touches, let touches = event.allTouches else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let point = touch.location(in: touch.window)
            switch touch.phase {
            case .began:
                starts[key] = Start(point: point, time: touch.timestamp, farthest: 0)
                flowMark("CHIPTOUCH start x=\(Int(point.x)) y=\(Int(point.y)) radius=\(Int(touch.majorRadius)) "
                         + "view=\(touch.view.map { String(describing: type(of: $0)) } ?? "-") "
                         + "fenster=\(touch.window.map { String(describing: type(of: $0)) } ?? "-") "
                         + "scrolls=[\(scrollState(at: point, in: touch.window))]")
            case .moved, .stationary:
                guard var start = starts[key] else { continue }
                start.farthest = max(start.farthest, hypot(point.x - start.point.x, point.y - start.point.y))
                starts[key] = start
            case .ended, .cancelled:
                guard let start = starts.removeValue(forKey: key) else { continue }
                let farthest = max(start.farthest, hypot(point.x - start.point.x, point.y - start.point.y))
                flowMark("CHIPTOUCH ende phase=\(touch.phase == .ended ? "ended" : "cancelled") "
                         + "dauer_ms=\(Int((touch.timestamp - start.time) * 1000)) weg=\(Int(farthest)) "
                         + "x=\(Int(point.x)) y=\(Int(point.y)) scrolls=[\(scrollState(at: start.point, in: touch.window))]")
            default:
                continue
            }
        }
    }

    private static func scrollState(at point: CGPoint, in window: UIWindow?) -> String {
        guard let window else { return "" }
        return ViewSearching.scrolls(in: window).compactMap { scroll -> String? in
            guard !(scroll is UITextView) else { return nil }
            let frame = scroll.convert(scroll.bounds, to: window)
            guard frame.contains(point) else { return nil }
            let axis = scroll.contentSize.width > scroll.bounds.width + 1 ? "h" : "v"
            return "\(axis) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) "
                + "off=\(Int(scroll.contentOffset.x)),\(Int(scroll.contentOffset.y)) "
                + "tracking=\(scroll.isTracking) dragging=\(scroll.isDragging) "
                + "decel=\(scroll.isDecelerating) pan=\(scroll.panGestureRecognizer.state.rawValue)"
        }.joined(separator: " | ")
    }
}

extension UIApplication {
    @objc func chipProbeSendEvent(_ event: UIEvent) {
        ChipTouchLog.record(event)
        chipProbeSendEvent(event)
    }
}
#endif
