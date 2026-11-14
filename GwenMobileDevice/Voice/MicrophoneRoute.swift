import GwenMobileKit
import AVFoundation

enum BluetoothQuality: String, Equatable, Sendable {
    case full = "voll"
    case possible = "moeglich"
    case none = "keine"

    static func of(supported: Bool, enabled: Bool) -> BluetoothQuality {
        enabled ? .full : supported ? .possible : .none
    }
}

struct RoutePort: Equatable, Sendable {
    let kind: String
    let name: String
    let quality: BluetoothQuality?
}

enum MicrophoneRoute {
    static func line(inputs: [RoutePort], outputs: [RoutePort]) -> String {
        "eingang=\(describe(inputs)) ausgang=\(describe(outputs))"
    }

    static func reason(_ raw: UInt?) -> String {
        switch raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) {
        case .newDeviceAvailable: return "neues_geraet"
        case .oldDeviceUnavailable: return "geraet_weg"
        case .categoryChange: return "kategorie"
        case .override: return "umgeleitet"
        case .wakeFromSleep: return "aufgewacht"
        case .noSuitableRouteForCategory: return "kein_weg"
        case .routeConfigurationChange: return "konfiguration"
        case .unknown, .none: return "unbekannt"
        @unknown default: return "unbekannt"
        }
    }

    static func available(_ session: AVAudioSession = .sharedInstance()) -> String {
        let ports = (session.availableInputs ?? []).map { "\($0.portType.rawValue)[\($0.portName)]" }
        return ports.isEmpty ? "-" : ports.joined(separator: ",")
    }

    static func current(_ session: AVAudioSession = .sharedInstance()) -> String {
        describe(session.currentRoute)
    }

    static func describe(_ route: AVAudioSessionRouteDescription) -> String {
        line(inputs: route.inputs.map(port), outputs: route.outputs.map(port))
    }

    private static func describe(_ ports: [RoutePort]) -> String {
        guard !ports.isEmpty else { return "-" }
        return ports.map { port in
            "\(port.kind)[\(port.name)]" + (port.quality.map { " qualitaet=\($0.rawValue)" } ?? "")
        }.joined(separator: ",")
    }

    private static func port(_ description: AVAudioSessionPortDescription) -> RoutePort {
        RoutePort(kind: description.portType.rawValue, name: description.portName,
                  quality: bluetoothQuality(of: description))
    }

    private static func bluetoothQuality(of description: AVAudioSessionPortDescription) -> BluetoothQuality? {
        guard let capability = description.bluetoothMicrophoneExtension?.highQualityRecording else { return nil }
        return BluetoothQuality.of(supported: capability.isSupported, enabled: capability.isEnabled)
    }
}
