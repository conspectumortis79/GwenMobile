@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
@preconcurrency import ActivityKit
#endif

@MainActor
enum ListenLiveActivityBridge {
    static func apply(_ plan: ListenLivePlan) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        ListenLiveActivity.shared.apply(plan)
        #endif
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
@MainActor
final class ListenLiveActivity {
    static let shared = ListenLiveActivity()

    private var activity: Activity<ListeningActivityAttributes>?
    private var current = ListenLivePlan.hidden
    private var startedAt = Date()

    func apply(_ plan: ListenLivePlan) {
        guard plan != current else { return }
        current = plan
        switch plan {
        case .hidden:
            end()
        case .visible(let mode, let phase, let titleKey):
            let title = L.t(titleKey)
            if let activity {
                let state = ListeningActivityAttributes.ContentState(phase: phase.attributesPhase,
                                                                     title: title,
                                                                     startedAt: startedAt)
                Task { @MainActor in
                    await activity.update(ActivityContent(state: state, staleDate: staleDate))
                }
            } else {
                start(mode: mode, phase: phase, title: title)
            }
        }
    }

    private func start(mode: ListenLivePlan.Mode, phase: ListenLivePlan.Phase, title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            current = .hidden
            return
        }
        startedAt = Date()
        let state = ListeningActivityAttributes.ContentState(phase: phase.attributesPhase,
                                                             title: title,
                                                             startedAt: startedAt)
        do {
            activity = try Activity.request(attributes: ListeningActivityAttributes(mode: mode.attributesMode),
                                            content: ActivityContent(state: state, staleDate: staleDate),
                                            pushType: nil)
            flowMark("LIVEACTIVITY start phase=\(phase) modus=\(mode)")
        } catch {
            current = .hidden
            flowMark("LIVEACTIVITY fehler " + TextLine.oneLine(error.localizedDescription, limit: 120))
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        flowMark("LIVEACTIVITY ende")
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private var staleDate: Date { Date().addingTimeInterval(4 * 60 * 60) }
}

private extension ListenLivePlan.Phase {
    var attributesPhase: ListeningActivityAttributes.ContentState.Phase {
        switch self {
        case .armed:
            return .armed
        case .recording:
            return .recording
        case .processing:
            return .processing
        }
    }
}

private extension ListenLivePlan.Mode {
    var attributesMode: ListeningActivityAttributes.Mode {
        switch self {
        case .listen:
            return .listen
        case .conversation:
            return .conversation
        }
    }
}
#endif
