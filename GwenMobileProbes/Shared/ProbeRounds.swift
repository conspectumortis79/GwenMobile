#if DEBUG
import GwenMobileKit

enum ProbeRounds {
    static let maximum = 2

    static func capped<T>(_ items: [T]) -> [T] {
        Array(items.prefix(maximum))
    }
}
#endif
