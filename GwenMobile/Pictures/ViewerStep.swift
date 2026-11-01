enum ViewerStep {
    case back
    case forward

    var delta: Int { self == .back ? -1 : 1 }

    func target(from index: Int, count: Int) -> Int? {
        let moved = index + delta
        guard count > 1, moved >= 0, moved < count else { return nil }
        return moved
    }
}
