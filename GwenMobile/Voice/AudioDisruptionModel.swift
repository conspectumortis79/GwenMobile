import AVFoundation

enum AudioDisruption: Equatable, Sendable {
    case began
    case ended
    case reconfigured

    static func interruption(_ rawType: UInt?) -> AudioDisruption? {
        switch rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
        case .began: return .began
        case .ended: return .ended
        case .none: return nil
        @unknown default: return nil
        }
    }
}

@MainActor
protocol AudioDisruptionWatching: AnyObject {
    func start(_ handler: @escaping @MainActor (AudioDisruption) async -> Void)
    func stop()
}
