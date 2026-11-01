@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import UIKit

@MainActor
final class AudioDisruptionWatcher: AudioDisruptionWatching {
    private var tokens: [NSObjectProtocol] = []
    private var handler: (@MainActor (AudioDisruption) async -> Void)?

    func start(_ handler: @escaping @MainActor (AudioDisruption) async -> Void) {
        self.handler = handler
        guard tokens.isEmpty else { return }
        observe(AVAudioSession.interruptionNotification, label: "unterbrechung") { note in
            AudioDisruption.interruption(note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
        }
        observe(AVAudioSession.mediaServicesWereResetNotification, label: "mediendienste") { _ in .ended }
        observe(.AVAudioEngineConfigurationChange, label: "konfiguration") { _ in .reconfigured }
        observe(UIApplication.didBecomeActiveNotification, label: "vordergrund") { _ in .ended }
        observe(AVAudioSession.routeChangeNotification, label: "weg") { note in
            let reason = MicrophoneRoute.reason(note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousText = previous.map(MicrophoneRoute.describe) ?? "-"
            Task.detached(priority: .utility) {
                let line = "MIKRO wegwechsel grund=\(reason) " + MicrophoneRoute.current()
                    + " vorher=[\(previousText)]" + " verfuegbar=\(MicrophoneRoute.available())"
                await MainActor.run { flowMarkPersonal(line) }
            }
            return .reconfigured
        }
        if #available(iOS 27.0, *) {
            observe(AVAudioSession.didBecomeInactiveNotification, label: "inaktiv") { _ in .began }
            observe(AVAudioSession.resumptionRecommendationNotification, label: "fortsetzen") { _ in .ended }
        }
    }

    func stop() {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
        tokens = []
        handler = nil
    }

    private func observe(_ name: Notification.Name, label: String,
                         as event: @escaping @Sendable (Notification) -> AudioDisruption?) {
        tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            guard let disruption = event(note) else { return }
            flowMark("MIKRO störung=\(label) art=\(disruption)")
            Task { @MainActor [weak self] in await self?.handler?(disruption) }
        })
    }
}
