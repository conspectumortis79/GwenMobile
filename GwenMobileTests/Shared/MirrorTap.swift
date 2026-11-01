import SwiftUI

private func castToMainActor<T>(_ value: T) -> (@MainActor () -> Void)? {
    unsafeBitCast(value, to: (@MainActor () -> Void).self)
}

@MainActor
enum MirrorTap {
    private final class Budget {
        var remaining = 200_000
    }

    private final class Seen {
        var objects: Set<ObjectIdentifier> = []
    }

    static func actions(in value: Any, depth: Int = 0) -> [@MainActor () -> Void] {
        collect(value, depth: depth, seen: Seen(), budget: Budget())
    }

    static func closure(from value: Any) -> (@MainActor () -> Void)? {
        _openExistential(value, do: castToMainActor)
    }

    private static func collect(_ value: Any, depth: Int, seen: Seen, budget: Budget)
        -> [@MainActor () -> Void] {
        guard depth < 32, budget.remaining > 0 else { return [] }
        var found: [@MainActor () -> Void] = []
        for child in Mirror(reflecting: value).children {
            budget.remaining -= 1
            if budget.remaining <= 0 { break }
            if isVoidAction(child.value), let action = closure(from: child.value) {
                found.append(action)
                continue
            }
            let object = child.value as AnyObject
            if String(describing: type(of: object)) != "_SwiftValue" {
                let identifier = ObjectIdentifier(object)
                if seen.objects.contains(identifier) { continue }
                seen.objects.insert(identifier)
            }
            found.append(contentsOf: collect(child.value, depth: depth + 1, seen: seen, budget: budget))
        }
        return found
    }

    private static func isVoidAction(_ value: Any) -> Bool {
        let name = String(describing: type(of: value))
        return name == "() -> ()" || name == "() -> Void"
            || name == "@MainActor () -> ()" || name == "@MainActor () -> Void"
            || name == "@Sendable () -> ()" || name == "@Sendable () -> Void"
            || name == "@MainActor @Sendable () -> ()" || name == "@MainActor @Sendable () -> Void"
    }
}
