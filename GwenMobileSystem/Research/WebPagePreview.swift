import SwiftUI
import WebKit

struct CodePreviewPage: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum WebPagePreviewPolicy {
    static func navigationPolicy(for url: URL?) -> WKNavigationActionPolicy {
        url?.absoluteString == "about:blank" ? .allow : .cancel
    }
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
        view.navigationDelegate = context.coordinator
        context.coordinator.reloadKey = reloadKey
        context.coordinator.load(url, into: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.reloadKey != reloadKey || context.coordinator.loadedURL != url else { return }
        context.coordinator.reloadKey = reloadKey
        context.coordinator.load(url, into: view)
    }

    @MainActor
    final class Loader: NSObject, WKNavigationDelegate {
        var reloadKey = 0
        var loadedURL: URL?

        func load(_ url: URL, into view: WKWebView) {
            loadedURL = url
            guard let html = try? String(contentsOf: url, encoding: .utf8) else {
                view.loadHTMLString("", baseURL: nil)
                return
            }
            view.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            WebPagePreviewPolicy.navigationPolicy(for: navigationAction.request.url)
        }
    }
}
