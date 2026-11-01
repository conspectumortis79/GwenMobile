@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UserNotifications

public struct GwenMobileApp: App {
    @StateObject private var store = ChatStore()
    @ObservedObject private var listens = ListenRequests.shared
    #if DEBUG
    @State private var testToken = 0
    @State private var testCmd = ""
    #endif
    #if targetEnvironment(macCatalyst)
    @ObservedObject private var macHelp = MacHelpRequests.shared
    @State private var showHelp = false
    #endif

    public init() {
        #if DEBUG
        ProbeSettingsGuard.restorePendingIfNeeded()
        #endif
        LocalRuntime.install()
        PriceWatchBackground.register()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        #if targetEnvironment(macCatalyst)
        ScrollAssertionShield.install()
        #endif
    }

    public var body: some Scene {
        #if targetEnvironment(macCatalyst)
        WindowGroup { rootContent }
            .commands {
                MacWindowCommands(onQuit: {
                    let store = self.store
                    Task { await store.flushPendingSave(); MacPresence.quit() }
                })
                MacHelpCommands()
            }
        #else
        WindowGroup { rootContent }
        #endif
    }

    func handle(_ url: URL) {
        if SpotifyLink.shared.handle(url) { return }
        if url.host == "listen" { listens.ask(from: "url") }
        #if DEBUG
        if url.host == "test" {
            testCmd = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
            testToken += 1
        }
        #endif
    }

    private var rootContent: some View {
        NavigationStack {
            #if DEBUG
            ChatView(listenToken: $listens.token, testToken: $testToken, testCmd: testCmd)
            #else
            ChatView(listenToken: $listens.token)
            #endif
        }
        .toolbar(.hidden, for: .navigationBar)
        .windowAppearance()
        .environmentObject(store)
        .onOpenURL(perform: handle)
        #if targetEnvironment(macCatalyst)
        .onChange(of: macHelp.token) { _, _ in showHelp = true }
        .sheet(isPresented: $showHelp) { MacHelpView() }
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("-gwenhelp") { showHelp = true }
        }
        #endif
        #endif
    }
}
