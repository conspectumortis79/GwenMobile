@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import WebKit

struct CodePreviewPage: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
struct WebPagePreview: View {
    let page: CodePreviewPage
    @Environment(\.dismiss) private var dismiss
    @State private var reloadKey = 0

    var body: some View {
        NavigationStack {
            PageWebView(url: page.url, reloadKey: reloadKey)
                .navigationTitle(page.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: TapProbe.action({ reloadKey += 1 })) {
                            Label(L.t("code_reload"), systemImage: "arrow.clockwise")
                        }
                        .accessibilityLabel(L.t("code_reload"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L.t("done"), action: TapProbe.action({ dismiss() }))
                    }
                }
        }
    }
}

private struct PageWebView: UIViewRepresentable {
    let url: URL
    let reloadKey: Int

    func makeCoordinator() -> Loader { Loader() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.backgroundColor = .systemBackground
        context.coordinator.reloadKey = reloadKey
        context.coordinator.load(url, into: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.reloadKey != reloadKey else { return }
        context.coordinator.reloadKey = reloadKey
        context.coordinator.load(url, into: view)
    }

    @MainActor
    final class Loader {
        var reloadKey = 0

        func load(_ url: URL, into view: WKWebView) {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}
