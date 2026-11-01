@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct CodeBlockView: View {
    static let maxVisibleHeight: CGFloat = 300
    static let minVisibleHeight: CGFloat = 44
    static let textLineHeight: CGFloat = 15.5
    static let textVerticalPadding: CGFloat = 16

    let block: CodeBlock
    var question: String? = nil
    var streaming: Bool = false
    private let actions: CodeCardActions
    #if DEBUG
    var probeRendered: (() -> Void)? = nil
    #endif
    @StateObject private var notice = NoticeLine()
    @StateObject private var copyState = AnswerCopyController()
    @State private var preview: CodePreviewPage?

    init(block: CodeBlock, question: String? = nil, streaming: Bool = false,
         actions: CodeCardActions = CodeCardActions(),
         probeRendered: (() -> Void)? = nil) {
        self.block = block
        self.question = question
        self.streaming = streaming
        self.actions = actions
        #if DEBUG
        self.probeRendered = probeRendered
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            codeArea
            if let note = notice.text {
                Text(verbatim: note)
                    .scaledFont(11)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 10).padding(.bottom, 7)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.systemGray4), lineWidth: 0.7)
        )
        .fullScreenCover(item: $preview) { page in
            WebPagePreview(page: page)
        }
        #if DEBUG
        .onAppear { probeRendered?() }
        #endif
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: block.language.label)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Color(.secondaryLabel))
            Text(verbatim: "· \(L.counted(block.lineCount, one: "code_lines_one", many: "code_lines"))")
                .scaledFont(11)
                .foregroundStyle(Color(.tertiaryLabel))
                .lineLimit(1)
            Spacer(minLength: 6)
            if block.language.opensInBrowser, !streaming {
                cardAction("play.rectangle", L.t("code_preview"),
                           TapProbe.action { run(actions.preview(block, question: question)) })
            }
            cardAction("arrow.down.to.line", L.t("code_download"),
                       TapProbe.action { run(actions.download(block, question: question)) })
            cardAction("square.and.arrow.up", L.t("code_share"),
                       TapProbe.action { run(actions.share(block, question: question)) })
            cardAction(copyState.confirmed ? "checkmark" : "doc.on.doc", L.t("code_copy"),
                       TapProbe.action { copyState.perform(block.code) })
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.systemGray5))
    }

    private var codeArea: some View {
        ScrollView([.horizontal, .vertical]) {
            ScrollViewReader { proxy in
                Text(verbatim: block.code)
                    .scaledFont(12.5, design: .monospaced)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .suppressingTextFocusRing()
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .id(Self.tailID)
                    .onAppear { if streaming { proxy.scrollTo(Self.tailID, anchor: .bottomLeading) } }
                    .onChange(of: block.code) { _, _ in
                        guard streaming else { return }
                        proxy.scrollTo(Self.tailID, anchor: .bottomLeading)
                    }
            }
        }
        .frame(height: visibleHeight)
    }

    private var visibleHeight: CGFloat {
        let needed = CGFloat(block.lineCount) * Self.textLineHeight + Self.textVerticalPadding
        return min(max(needed, Self.minVisibleHeight), Self.maxVisibleHeight)
    }

    private func cardAction(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(14)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func run(_ outcome: CodeCardOutcome) {
        switch outcome {
        case .nothing:
            break
        case .notice(let note):
            notice.show(note)
        case .preview(let page):
            preview = page
        }
    }

    private static let tailID = "gwen-code-tail"
}
