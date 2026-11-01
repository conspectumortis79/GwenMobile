protocol ChipRef: Equatable {
    var chipID: String { get }
    var isOpenable: Bool { get }
}

enum ChipOutcome<Ref: ChipRef>: Equatable {
    case present(Ref)
    case accessMissing
    case gone
}

enum ChipGate {
    @MainActor
    static func outcome<Ref: ChipRef>(for ref: Ref, hasAccess: Bool,
                                      isLive: @MainActor (String) -> Bool) -> ChipOutcome<Ref> {
        guard ref.isOpenable else { return .gone }
        guard hasAccess else { return .accessMissing }
        guard isLive(ref.chipID) else { return .gone }
        return .present(ref)
    }
}
