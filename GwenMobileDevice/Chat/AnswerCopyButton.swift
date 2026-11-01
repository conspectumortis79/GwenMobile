@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
final class AnswerCopyController: TimedFlag<Bool> {
    static let defaultConfirmDuration: Duration = .milliseconds(1600)

    private let pasteboard: PasteboardWriting

    var confirmed: Bool { value }

    init(pasteboard: PasteboardWriting = SystemPasteboard(),
         confirmDuration: Duration = AnswerCopyController.defaultConfirmDuration) {
        self.pasteboard = pasteboard
        super.init(false, resetTo: false, after: confirmDuration)
    }

    func perform(_ text: String) {
        pasteboard.write(text)
        set(true)
    }
}

@MainActor
struct AnswerCopyButton: View {
    private let text: String
    @StateObject private var controller: AnswerCopyController

    init(text: String, controller: AnswerCopyController = AnswerCopyController()) {
        self.text = text
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        Button(action: TapProbe.action({ controller.perform(text) })) {
            HStack(spacing: 5) {
                Image(systemName: controller.confirmed ? "checkmark" : "doc.on.doc")
                    .scaledFont(14)
                    .contentTransition(.symbolEffect(.replace))
                if controller.confirmed {
                    Text(L.t("copied"))
                        .scaledFont(12, weight: .semibold)
                }
            }
            .foregroundStyle(controller.confirmed ? Color(.systemGreen) : Color(.tertiaryLabel))
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: controller.confirmed)
        .accessibilityLabel(L.t("copy_answer"))
    }
}

@MainActor
struct AnswerCopyMenuItem: View {
    private let text: String
    private let pasteboard: PasteboardWriting
    private let onCopied: () -> Void

    init(text: String, pasteboard: PasteboardWriting = SystemPasteboard(),
         onCopied: @escaping () -> Void = {}) {
        self.text = text
        self.pasteboard = pasteboard
        self.onCopied = onCopied
    }

    var body: some View {
        Button(action: TapProbe.action({
            pasteboard.write(text)
            onCopied()
        })) {
            Label(L.t("copy_answer"), systemImage: "doc.on.doc")
        }
    }
}
