import GwenMobileKit
import Foundation

@MainActor
public final class ListenRequests: ObservableObject {
    public static let shared = ListenRequests()

    @Published var token = 0

    public func ask(from source: String) {
        flowMark("LISTEN anfrage quelle=\(source)")
        token += 1
    }
}
