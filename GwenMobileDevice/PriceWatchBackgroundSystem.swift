import GwenMobileKit
import BackgroundTasks
import Foundation

final class PriceWatchBackgroundSystem: PriceWatchBackgroundScheduling {
    static let shared = PriceWatchBackgroundSystem()

    static let taskIdentifier = "com.mortis.gwenmobile.pricecheck"
    static let minimumDelay: TimeInterval = 15 * 60

    @MainActor
    private static let registered = LockedValue(false)

    #if !targetEnvironment(macCatalyst)
    nonisolated(unsafe) static var submit: @MainActor (BGAppRefreshTaskRequest) throws -> Void = {
        try BGTaskScheduler.shared.submit($0)
    }

    nonisolated(unsafe) static var cancelScheduled: @MainActor (String) -> Void = {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: $0)
    }
    #endif

    @MainActor
    func register() {
        #if !targetEnvironment(macCatalyst)
        guard Self.registered.exchange(true) == false else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            Self.accept(task as? BGAppRefreshTask)
        }
        #endif
    }

    @MainActor
    static func accept(_ task: BGAppRefreshTask?) {
        Task { @MainActor in
            await PriceWatchBackgroundPort.current.handle(task)
        }
    }

    @MainActor
    func scheduleNext(store: PriceWatchStore = PriceWatchStore(), now: Date = Date()) async {
        #if !targetEnvironment(macCatalyst)
        guard let next = await store.nextDueDate() else {
            Self.cancelScheduled(Self.taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = max(next, now.addingTimeInterval(Self.minimumDelay))
        do {
            try Self.submit(request)
            flowMark("PREISWECKER hintergrund geplant fuer=\(Formatters.eventDateTime(request.earliestBeginDate ?? now))")
        } catch {
            flowMark("PREISWECKER hintergrund planung fehlgeschlagen "
                     + "grund=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
        }
        #endif
    }

    @MainActor
    func handle(_ task: BGAppRefreshTask?) async {
        let settings = AppSettings.shared
        settings.reloadBlockedKeys()
        let store = PriceWatchStore()
        let credentials = PriceWatchCredentials(settings: settings)
        let runner = PriceWatchFlowRunner(store: store,
                                          checker: LivePriceWatchChecker(lookup: WebPriceLookup { _ in }),
                                          credentials: credentials,
                                          notifier: LocalPriceWatchNotifier())
        let started = ContinuousClock.now
        let configured = settings.isConfigured
        let work = Task { @MainActor in
            guard configured else { return 0 }
            return await runner.checkDue().count
        }
        task?.expirationHandler = { work.cancel() }
        let hits = await work.value
        let expired = work.isCancelled
        await complete(task: task, store: store, configured: configured, expired: expired,
                       hits: hits, started: started)
    }

    @MainActor
    func complete(task: BGAppRefreshTask?, store: PriceWatchStore, configured: Bool, expired: Bool,
                  hits: Int, started: ContinuousClock.Instant) async {
        await scheduleNext(store: store)
        flowMark("PREISWECKER hintergrund geprueft=\(configured) treffer=\(hits) "
                 + "abgelaufen=\(expired) ms=\(msOf(started.duration(to: .now)))")
        task?.setTaskCompleted(success: configured && !expired)
    }
}
