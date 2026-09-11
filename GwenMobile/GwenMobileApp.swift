import SwiftUI

@main
struct GwenMobileApp: App {
    @StateObject private var store = ChatStore()
    @State private var listenToken = 0
    @State private var testToken = 0
    @State private var testCmd = ""

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView(listenToken: $listenToken, testToken: $testToken, testCmd: testCmd)
            }
            .toolbar(.hidden, for: .navigationBar)
            .environmentObject(store)
            .onOpenURL { url in
                if url.host == "listen" { listenToken += 1 }
                if url.host == "test" {
                    testCmd = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
                    testToken += 1
                }
            }
        }
    }
}
