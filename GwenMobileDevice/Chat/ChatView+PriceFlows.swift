@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runPriceSearch(terms: [String], country: String?, nearby: Bool,
                                           question: String, pictures: [Data],
                                           history: [ChatMessage], convID: UUID, started: Date,
                                           slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let model = settings.chatModel
        let region = await priceRegions.region(named: PriceRegion.claimed(country, in: question)?.code,
                                               whenLocalWish: nearby)
        guard !Task.isCancelled else { return }
        let finding = await readProduct(in: pictures, question: question)
        guard !Task.isCancelled else { return }
        let comparator = PriceComparator(lookup: WebPriceLookup { status in
            markStatus(slot?.step ?? 0, status)
        })
        do {
            let outcome = try await busy.running(L.t("price_working")) {
                try await comparator.compare(baseURL: settings.baseURL, key: settings.apiKey, model: model,
                                             question: question, terms: terms, finding: finding,
                                             region: region, history: history,
                                             thinking: settings.thinkingDirective(for: model))
            }
            guard !Task.isCancelled else { return }
            finishAnswer(outcome.text, artifacts: AnswerArtifacts(sources: outcome.sources,
                                                                 sourcesHeadingKey: outcome.headingKey),
                         model: model, convID: convID, started: started, slot: slot)
        } catch {
            guard !Task.isCancelled else { return }
            flowMarkPersonal("PREISSUCHE fehl geschlagen model=\(model) \(region.traceLine) "
                             + "begründung=\(TextLine.oneLine(error.localizedDescription, limit: 80))")
            appendAnswerFailure(error, genericKey: "err_web_generic", model: model,
                                convID: convID, started: started, slot: slot)
        }
    }

    @MainActor func runPriceWatchFlow(_ request: PriceWatchRequest, question: String, convID: UUID,
                                              started: Date, slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let credentials = PriceWatchCredentials(settings: settings)
        let runner = PriceWatchFlowRunner(store: store.watches,
                                          checker: priceWatchDesk.checker { status in
                                              markStatus(slot?.step ?? 0, status)
                                          },
                                          credentials: credentials,
                                          notifier: priceWatchDesk.notifier())
        let outcome = await withBusy(L.t("price_watch_working")) {
            await runner.run(request, question: question)
        }
        guard !Task.isCancelled else { return }
        await PriceWatchBackground.scheduleNext(store: store.watches)
        flowMarkPersonal("PREISWECKER schritt=\(request.action.rawValue) \(request.stepWords)")
        finishAnswer(outcome.text, artifacts: AnswerArtifacts(priceWatchRef: outcome.ref),
                     model: settings.chatModel, convID: convID, started: started, slot: slot)
    }

    @MainActor func checkPriceWatches() async {
        guard !Task.isCancelled else { return }
        guard settings.isConfigured else { return }
        guard !priceWatchCatchUpRunning else { return }
        priceWatchCatchUpRunning = true
        defer { priceWatchCatchUpRunning = false }
        let due = await store.watches.due()
        guard !Task.isCancelled else { return }
        guard !due.isEmpty else { return }
        let credentials = PriceWatchCredentials(settings: settings)
        let runner = PriceWatchFlowRunner(store: store.watches,
                                          checker: priceWatchDesk.checker { _ in },
                                          credentials: credentials,
                                          notifier: priceWatchDesk.notifier())
        let hits = await runner.checkDue()
        guard !Task.isCancelled else { return }
        await PriceWatchBackground.scheduleNext(store: store.watches)
        guard !Task.isCancelled else { return }
        guard let convID = store.current?.id else { return }
        for hit in hits {
            guard !Task.isCancelled else { return }
            guard let offer = hit.offer else { continue }
            let text = PriceWatchAnswers.alarm(hit.watch, offer: offer)
            store.appendAssistant(text, model: settings.chatModel, elapsed: nil, to: convID,
                                  priceWatch: PriceWatchRef(watch: hit.watch))
            announceAnswer(text)
            flowMarkPersonal("PREISWECKER frist hit produkt=\(hit.watch.product)")
        }
    }

}
