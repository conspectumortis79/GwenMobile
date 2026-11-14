#if DEBUG
import AVFoundation
import Foundation

private struct PortBox: @unchecked Sendable {
    let port: AVAudioSessionPortDescription?
}

enum ProbeAudioSession {
    private static let queue = DispatchQueue(label: "com.mortis.gwenmobile.probe-audio")

    static func setPreferredInput(_ port: AVAudioSessionPortDescription?) async throws {
        let box = PortBox(port: port)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try AVAudioSession.sharedInstance().setPreferredInput(box.port)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static func overrideOutput(_ option: AVAudioSession.PortOverride) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(option)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                            options: AVAudioSession.CategoryOptions) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
#endif
