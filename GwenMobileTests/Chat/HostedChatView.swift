@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
@testable import GwenMobileProbes
import GwenMobileKit
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HostedChatView {
    static let appearWait: Duration = .milliseconds(900)

    private var captured: ChatView?
    private var window: UIWindow?
    private var previousKey: UIWindow?

    nonisolated init() {}

    static func store(_ paths: StoragePaths, persistence: (any ConversationPersisting)? = nil) -> ChatStore {
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths, persistence: persistence)
        store.newConversation()
        return store
    }

    func open(_ store: ChatStore, in test: XCTestCase) async throws -> ChatView {
        ProbeHook.appear = { [weak self] view in
            guard let self, view.store === store else { return }
            self.captured = view
        }
        previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return try await host(ChatView(listenToken: .constant(0)).environmentObject(store), in: test)
    }

    func host(_ root: some View, in test: XCTestCase, settle: Duration = appearWait) async throws -> ChatView {
        closeWindow()
        captured = nil
        guard let host = test.hostWindow(root) else { throw APIError(message: "kein Hosting-Fenster") }
        window = host
        try await Task.sleep(for: settle)
        guard let view = captured else { throw APIError(message: "ChatView nicht gefangen") }
        return view
    }

    func closeWindow() {
        if let window { ProbeHosting.close(window) }
        window = nil
    }

    @discardableResult
    func close() -> Bool {
        ProbeHook.appear = nil
        closeWindow()
        let restored = previousKey != nil
        previousKey?.makeKeyAndVisible()
        previousKey = nil
        captured = nil
        return restored
    }
}
