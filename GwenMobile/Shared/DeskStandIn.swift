#if DEBUG
struct DeskStandIn<Value> {
    private var kept: Value?

    mutating func stand(_ replacement: Value, over current: inout Value) {
        if kept == nil { kept = current }
        current = replacement
    }

    mutating func restore(_ current: inout Value) {
        guard let kept else { return }
        current = kept
        self.kept = nil
    }
}
#endif
