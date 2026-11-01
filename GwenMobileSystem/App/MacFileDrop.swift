@testable import GwenMobileFeatureCore
import SwiftUI
import Foundation
import UniformTypeIdentifiers

extension View {
    @ViewBuilder func macFileDrop(_ accept: @escaping @MainActor ([URL]) -> Void) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacFileDropModifier(accept: accept))
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
struct MacFileDropModifier: ViewModifier {
    let accept: @MainActor ([URL]) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(WindowDropBridge(isTargeted: $isTargeted, accept: accept))
            .overlay {
                if isTargeted {
                    dropHint
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }

    private var dropHint: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.08))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [9, 6]))
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .scaledFont(30)
                Text(L.t("drop_hint"))
                    .scaledFont(15, weight: .semibold)
            }
            .foregroundStyle(Color.blue)
        }
        .padding(8)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private struct WindowDropBridge: UIViewRepresentable {
    @Binding var isTargeted: Bool
    let accept: @MainActor ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted, accept: accept)
    }

    func makeUIView(context: Context) -> UIView {
        let view = DropHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isTargeted = $isTargeted
        context.coordinator.accept = accept
    }

    @MainActor final class Coordinator: NSObject, UIDropInteractionDelegate {
        var isTargeted: Binding<Bool>
        var accept: @MainActor ([URL]) -> Void
        private weak var attachedWindow: UIWindow?
        private var interaction: UIDropInteraction?

        init(isTargeted: Binding<Bool>, accept: @escaping @MainActor ([URL]) -> Void) {
            self.isTargeted = isTargeted
            self.accept = accept
            super.init()
        }

        func attach(to window: UIWindow?) {
            guard let window, window !== attachedWindow else { return }
            if let interaction, let attachedWindow {
                attachedWindow.removeInteraction(interaction)
            }
            let interaction = UIDropInteraction(delegate: self)
            window.addInteraction(interaction)
            self.interaction = interaction
            attachedWindow = window
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            Self.isFileDrop(session)
        }

        static func isFileDrop(_ session: UIDropSession) -> Bool {
            for item in session.items {
                let identifiers = item.itemProvider.registeredTypeIdentifiers
                if identifiers.contains(UTType.fileURL.identifier) { return true }
                if identifiers.contains("com.apple.finder.node") { return true }
            }
            return false
        }

        func dropInteraction(_ interaction: UIDropInteraction,
                             sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            isTargeted.wrappedValue = true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, concludeDrop session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            let providers = session.items.map(\.itemProvider)
            isTargeted.wrappedValue = false
            Task { @MainActor in
                let urls = await Self.fileURLs(from: providers)
                guard !urls.isEmpty else { return }
                accept(urls)
            }
        }

        @MainActor
        private static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
            var found: [URL] = []
            for provider in providers {
                if let picked = await fileURL(from: provider) { found.append(picked) }
            }
            var seen = Set<String>()
            return found.filter { seen.insert($0.absoluteString).inserted }
        }

        @MainActor
        private static func fileURL(from provider: NSItemProvider) async -> URL? {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let direct = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        continuation.resume(returning: Self.url(from: item))
                    }
                }
                if let direct { return direct }
            }
            let candidates = provider.registeredTypeIdentifiers.filter { $0 != "com.apple.finder.node" }
            for identifier in candidates {
                let inPlace = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    provider.loadInPlaceFileRepresentation(forTypeIdentifier: identifier) { url, _, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let inPlace { return inPlace }
            }
            return nil
        }

        private nonisolated static func url(from item: NSSecureCoding?) -> URL? {
            if let item = item as? URL { return item }
            if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
            if let text = item as? String { return URL(string: text) }
            return nil
        }
    }
}

private final class DropHostView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
#endif
