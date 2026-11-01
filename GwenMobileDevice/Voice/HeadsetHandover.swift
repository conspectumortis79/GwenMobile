@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation

enum BluetoothPorts {
    static let kinds: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]

    static func ids(in route: AVAudioSessionRouteDescription?) -> Set<String> {
        guard let route else { return [] }
        return Set((route.inputs + route.outputs).filter { kinds.contains($0.portType) }.map(\.uid))
    }

    static func availableInputs(_ session: AVAudioSession = .sharedInstance()) -> Set<String> {
        Set((session.availableInputs ?? []).map(\.uid))
    }

    static func change(from note: Notification, session: AVAudioSession = .sharedInstance()) -> RouteChange {
        let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        return RouteChange(deviceLeft: reason == .oldDeviceUnavailable, deviceArrived: reason == .newDeviceAvailable,
                           previousBluetooth: ids(in: previous), currentBluetooth: ids(in: session.currentRoute),
                           available: availableInputs(session))
    }
}

@MainActor
final class HeadsetHandover: HeadsetHandling {
    private static let sessionQueue = DispatchQueue(label: "com.mortis.gwenmobile.headset")
    private var policy: HeadsetHandoverPolicy?
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        policy = HeadsetHandoverPolicy()
        token = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                       object: nil, queue: .main) { [weak self] note in
            let change = BluetoothPorts.change(from: note)
            Task { @MainActor [weak self] in self?.follow(change) }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        if policy?.yielded.isEmpty == false { reclaim(preferring: []) }
        policy = nil
    }

    func follow(_ change: RouteChange) {
        guard var policy else { return }
        let move = policy.decide(change)
        self.policy = policy
        switch move {
        case .none:
            return
        case .yield:
            yieldToPhone()
        case .reclaim(let headsets):
            reclaim(preferring: headsets)
        }
    }

    func yieldToPhone() {
        Self.sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            var failures: [String] = []
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }),
               session.preferredInput?.uid != builtIn.uid {
                do { try session.setPreferredInput(builtIn) } catch {
                    failures.append("eingang=\((error as NSError).code)")
                }
            }
            if !session.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
                do { try session.overrideOutputAudioPort(.speaker) } catch {
                    failures.append("ausgang=\((error as NSError).code)")
                }
            }
            let line = "MIKRO headset freigegeben fehler=\(failures.isEmpty ? "-" : failures.joined(separator: ",")) "
                + MicrophoneRoute.current(session)
            Task { @MainActor in flowMarkPersonal(line) }
        }
    }

    func reclaim(preferring headsets: Set<String>) {
        Self.sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            let headset = session.availableInputs?.first { headsets.contains($0.uid) }
            var failures: [String] = []
            do { try session.overrideOutputAudioPort(.none) } catch {
                failures.append("ausgang=\((error as NSError).code)")
            }
            do { try session.setPreferredInput(headset) } catch {
                failures.append("eingang=\((error as NSError).code)")
            }
            let line = "MIKRO headset zurueck bevorzugt=\(headset?.portName ?? "-") "
                + "fehler=\(failures.isEmpty ? "-" : failures.joined(separator: ",")) "
                + MicrophoneRoute.current(session)
            Task { @MainActor in flowMarkPersonal(line) }
        }
    }
}
