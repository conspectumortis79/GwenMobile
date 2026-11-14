import GwenMobileKit
import Foundation

@MainActor
struct PlaceFlowOutcome {
    let text: String
    let hits: [NearbyHit]
    let headingKey: String

    var places: [NearbyPlace] { hits.map(\.place) }
}

@MainActor
struct PlaceFlowCopy {
    let busyKey: String
    let headingKey: String
    let failureKey: String
    let showsDistance: Bool
}

@MainActor
struct PlaceFlowRunner {
    enum Kind {
        case nearby
        case route

        var copy: PlaceFlowCopy {
            switch self {
            case .nearby:
                return PlaceFlowCopy(busyKey: "place_working", headingKey: "place_head",
                                     failureKey: "place_none_found", showsDistance: true)
            case .route:
                return PlaceFlowCopy(busyKey: "route_working", headingKey: "route_head",
                                     failureKey: "route_not_found", showsDistance: false)
            }
        }
    }

    private let search: NearbyPlacing
    private let model: String?

    init(search: NearbyPlacing, model: String?) {
        self.search = search
        self.model = model
    }

    func run(_ kind: Kind, terms: [String], wish: String, mode: TravelMode,
             count: Int? = nil) async -> PlaceFlowOutcome {
        let copy = kind.copy
        do {
            let hits = try await matches(kind, terms: terms, wish: wish, mode: mode, count: count)
            let heading = headingKey(copy, hits: hits)
            return PlaceFlowOutcome(text: present(copy, headingKey: heading, hits: hits), hits: hits,
                                    headingKey: heading)
        } catch {
            return PlaceFlowOutcome(text: failureText(copy, error: error), hits: [],
                                    headingKey: copy.headingKey)
        }
    }

    private func matches(_ kind: Kind, terms: [String], wish: String, mode: TravelMode,
                         count: Int?) async throws -> [NearbyHit] {
        switch kind {
        case .nearby: return try await search.places(matching: terms, wish: wish, mode: mode, count: count)
        case .route: return try await search.route(to: terms, wish: wish, mode: mode, count: count)
        }
    }

    private func failureText(_ copy: PlaceFlowCopy, error: Error) -> String {
        let raw = (error as? APIError)?.message ?? error.localizedDescription
        let localKeys = [copy.failureKey, "place_denied", "place_unavailable", "place_busy"]
        if localKeys.contains(where: { L.t($0) == raw }) { return AnswerError.marker + raw }
        return AnswerError.other(error, model: model, generic: L.t(copy.failureKey))
    }

    private func headingKey(_ copy: PlaceFlowCopy, hits: [NearbyHit]) -> String {
        guard copy.showsDistance, !hits.isEmpty,
              hits.allSatisfy({ $0.place.metres == nil }) else { return copy.headingKey }
        return "place_head_area"
    }

    private func present(_ copy: PlaceFlowCopy, headingKey: String, hits: [NearbyHit]) -> String {
        let lines = hits.map { hit -> String in
            guard copy.showsDistance, let distance = hit.place.distanceText else { return "- " + hit.place.name }
            return "- \(hit.place.name) · \(distance)"
        }.joined(separator: "\n")
        return "\(L.t(headingKey))\n\(lines)"
    }
}
