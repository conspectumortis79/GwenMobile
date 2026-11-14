#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum ViewSearching {
    static func scrolls(in view: UIView, depth: Int = 0) -> [UIScrollView] {
        guard depth < 60 else { return [] }
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView { found.append(scroll) }
        for child in view.subviews { found.append(contentsOf: scrolls(in: child, depth: depth + 1)) }
        return found
    }

    static func all(in view: UIView, depth: Int = 0) -> [UIView] {
        guard depth < 60 else { return [] }
        var found: [UIView] = [view]
        for child in view.subviews { found.append(contentsOf: all(in: child, depth: depth + 1)) }
        return found
    }
}
#endif
