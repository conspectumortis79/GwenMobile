@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugSourceRetryProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "source_retry.txt")
        guard view.settings.isConfigured else {
            report.add("ABBRUCH", "kein schluessel konfiguriert")
            return
        }
        let question = "Aktuelle Nachrichten aus Berlin"
        let query = "aktuelle nachrichten"
        let region = Locale.current.region?.identifier.lowercased()
        let filterModel = view.settings.answeringModel(hasPictures: false)
        let research = WebResearch(onStatus: { _ in })
        var terms: [String] = []
        var filterCalls = 0
        do {
            let kept = try await WebSourceGathering.gather(
                query: query,
                question: question,
                retrieve: { term in
                    terms.append(term)
                    flowMark("RETRYPROBE suche=\"\(term)\"")
                    return try await research.hits(for: term) { term in
                        try await WebSearch.searchURLs(term, region: region)
                    }
                },
                filter: { hits in
                    filterCalls += 1
                    if filterCalls == 1 {
                        flowMark("RETRYPROBE filter leer simuliert quellen=\(hits.count)")
                        return []
                    }
                    return await ToolRouter.keptSources(baseURL: view.settings.baseURL,
                                                        key: view.settings.apiKey,
                                                        model: filterModel,
                                                        question: question, hits: hits,
                                                        thinking: view.settings.thinkingOffDirective(
                                                            for: filterModel)) { request in
                        try await HTTP.jsonData(request)
                    }
                })
            let first = terms.first ?? "-"
            let second = terms.count > 1 ? terms[1] : "-"
            report.add("RETRYPROBE", "suchtexte=\(terms.count) erster=\"\(first)\" zweiter=\"\(second)\" "
                       + "quellen=\(kept.count) domains=\(kept.map(\.domain).joined(separator: ",")) "
                       + "wiederholung_erfolgreich=\(!kept.isEmpty)")
        } catch {
            report.addFailure("RETRYPROBE", error)
        }
        flowLog.info("SOURCERETRY fertig")
    }
}
#endif
