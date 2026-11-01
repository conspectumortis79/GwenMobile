import Foundation

@MainActor
final class DayBriefingDesk: ObservableObject {
    private(set) var sources: DayBriefingSources

    init(sources: DayBriefingSources = .live()) {
        self.sources = sources
    }

    func service(includes: DayBriefingIncludes) -> DayBriefingService {
        DayBriefingService(sources: sources, includes: includes)
    }

    #if DEBUG
    private var standIn = DeskStandIn<DayBriefingSources>()

    func stand(in sources: DayBriefingSources) {
        standIn.stand(sources, over: &self.sources)
    }

    func restore() {
        standIn.restore(&sources)
    }
    #endif
}
