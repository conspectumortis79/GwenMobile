import SwiftUI
import Photos
import UIKit

struct Bubble: View, Equatable {
    final class AttrBox {
        let value: AttributedString
        init(_ v: AttributedString) { value = v }
    }

    static let mdCache: NSCache<NSString, AttrBox> = {
        let c = NSCache<NSString, AttrBox>()
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    let text: String
    let isUser: Bool
    var question: String? = nil
    var streaming: Bool = false
    var images: [Attachment] = []
    var outImages: [Attachment] = []
    var model: String? = nil
    var elapsed: Double? = nil
    var time: String? = nil
    var isLast: Bool = false
    var width: CGFloat = 360
    var onEdit: ((Attachment) -> Void)? = nil
    var onPreview: ((Attachment) -> Void)? = nil
    var messageID: UUID?
    var onDelete: ((UUID) -> Void)? = nil
    var sources: [WebSource] = []
    var thinking: ThinkingLevel? = nil
    let media: MediaStore?
    @State private var savedNote: String?
    @State private var shareFailure: String?

    init(message: ChatMessage, media: MediaStore, question: String? = nil, time: String? = nil,
         isLast: Bool = false,
         width: CGFloat = 360,
         onEdit: ((Attachment) -> Void)? = nil,
         onPreview: ((Attachment) -> Void)? = nil,
         onDelete: ((UUID) -> Void)? = nil) {
        self.text = message.text
        self.isUser = message.role == .user
        self.question = question
        self.images = message.images
        self.outImages = message.outImages ?? []
        self.model = message.model
        self.elapsed = message.elapsed
        self.time = time
        self.isLast = isLast
        self.width = width
        self.onEdit = onEdit
        self.onPreview = onPreview
        self.messageID = message.id
        self.onDelete = onDelete
        self.sources = message.sources ?? []
        self.thinking = message.thinking
        self.media = media
    }

    init(text: String, isUser: Bool, question: String? = nil, streaming: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.question = question
        self.streaming = streaming
        self.media = nil
        self.messageID = nil
    }

    nonisolated static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.text == rhs.text && lhs.isUser == rhs.isUser && lhs.streaming == rhs.streaming
            && lhs.question == rhs.question
            && lhs.images == rhs.images && lhs.outImages == rhs.outImages
            && lhs.model == rhs.model && lhs.elapsed == rhs.elapsed && lhs.time == rhs.time
            && lhs.isLast == rhs.isLast && lhs.sources == rhs.sources
            && lhs.thinking == rhs.thinking
            && lhs.messageID == rhs.messageID
            && lhs.width == rhs.width && lhs.media === rhs.media
    }

    var body: some View {
        #if DEBUG
        let _ = RenderStats.bubbleBody.bump()
        #endif
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    if !images.isEmpty {
                        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                            ForEach(images, id: \.file) { att in
                                Button(action: { openPreview(att) }) {
                                    AttachmentImage(att: att)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L.t("open_image"))
                                .contextMenu { imageActions(att, library: false) }
                            }
                        }
                    }
                    if !outImages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(outImages, id: \.file) { att in
                                Button(action: { openPreview(att) }) {
                                    AttachmentImage(att: att, fit: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L.t("open_image"))
                                .contextMenu { imageActions(att, library: true) }
                            }
                            HStack(spacing: 14) {
                                ForEach(Array(outImages.enumerated()), id: \.offset) { _, att in
                                    Button { saveAttachment(att) } label: {
                                        Label(L.t("save_to_photos"), systemImage: "square.and.arrow.down")
                                            .font(.system(size: 13))
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    if streaming && text.isEmpty {
                        ProcessingLabel(text: L.t("processing"))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(bubbleColor)
                            .clipShape(BubbleShape(isUser: isUser))
                    } else if !text.isEmpty {
                        renderedText
                            .font(.system(size: 17))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .environment(\.openURL, footnoteOpener)
                            .foregroundStyle(isUser ? Color.white : Color.primary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(bubbleColor)
                            .clipShape(BubbleShape(isUser: isUser))
                    }
                    if !sources.isEmpty {
                        sourcesView
                    }
                    if !isUser && !streaming, let model {
                        HStack(spacing: 5) {
                            Image(systemName: "brain.head.profile").font(.system(size: 10))
                            Text(verbatim: signatureLine(model: model))
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                    }
            }
            .frame(width: width, alignment: isUser ? .trailing : .leading)
            if let note = savedNote {
                Text(verbatim: note)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 14)
            }
            if isLast, let time {
                Text(verbatim: isUser ? "\(L.t("read")) \(time)" : time)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.horizontal, 14)
            }
        }
        .contextMenu {
            if !isUser && !text.isEmpty {
                Button { saveAsFile() } label: {
                    Label(L.t("save_as_file"), systemImage: "arrow.down.doc")
                }
            }
            if let messageID, let onDelete, !streaming {
                Button(role: .destructive) { onDelete(messageID) } label: {
                    Label(L.t("delete_message"), systemImage: "trash")
                }
            }
        }
        .alert(L.t("error"), isPresented: Binding(
            get: { shareFailure != nil },
            set: { if !$0 { shareFailure = nil } }
        )) {
            Button(L.t("ok"), role: .cancel) { shareFailure = nil }
        } message: {
            Text(verbatim: shareFailure ?? "")
        }
    }

    private func openPreview(_ att: Attachment) {
        onPreview?(att)
    }

    private func saveAsFile() {
        do {
            try Presenter.share(url: AnswerExporter().write(text: text, sources: sources, question: question,
                                                            model: model, elapsed: elapsed, time: time))
            savedNote = L.t("answers_saved")
        } catch {
            shareFailure = error.localizedDescription
        }
    }

    @ViewBuilder private func imageActions(_ att: Attachment, library: Bool) -> some View {
        Button { shareImage(att) } label: {
            Label(L.t("send_via_airdrop"), systemImage: "paperplane")
        }
        if library {
            Button { saveAttachment(att) } label: {
                Label(L.t("save_to_photos"), systemImage: "square.and.arrow.down")
            }
            if let onEdit {
                Button { onEdit(att) } label: {
                    Label(L.t("edit_this"), systemImage: "pencil")
                }
            }
        }
    }

    private func shareImage(_ att: Attachment) {
        guard let url = media?.storedURL(for: att) else {
            shareFailure = L.t("image_gone")
            return
        }
        do {
            try Presenter.share(url: url)
        } catch {
            shareFailure = error.localizedDescription
        }
    }

    private func signatureLine(model: String) -> String {
        var parts = [model]
        if let elapsed { parts.append(String(format: "%.1f s", elapsed)) }
        if let thinking { parts.append(thinking.label) }
        return parts.joined(separator: " · ")
    }

    private func openSource(_ s: WebSource) {
        guard let url = URL(string: s.url) else { return }
        if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
    }

    private func chipColor(_ domain: String) -> Color {
        var h: UInt64 = 1469598103934665603
        for b in domain.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return Color(hue: Double(h % 360) / 360, saturation: 0.55, brightness: 0.75)
    }

    private func domainInitial(_ domain: String) -> String {
        String(domain.split(separator: ".").last.map { $0.first.map(String.init) ?? "?" } ?? "?").uppercased()
    }

    private var sourcesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("web_sources_head"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
            HStack(spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.offset) { idx, s in
                    Button { openSource(s) } label: {
                        HStack(spacing: 5) {
                            Text(verbatim: domainInitial(s.domain))
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(chipColor(s.domain)))
                            Text(verbatim: s.domain)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(verbatim: "\(idx + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var renderedText: Text {
        if streaming { return Text(MarkdownRenderer.inline(text)) }
        return markdownText
    }

    private var markdownText: Text {
        let key = "s\(sources.count)\u{1}\(text)" as NSString
        if let hit = Self.mdCache.object(forKey: key) { return Text(hit.value) }
        var attr = MarkdownRenderer.inline(text)
        if !isUser && !sources.isEmpty, let regex = Self.footnoteRegex {
            let plain: String = String(attr.characters)
            let ns = plain as NSString
            let marks = regex.matches(in: plain, range: NSRange(location: 0, length: ns.length))
            for m in marks.reversed() {
                guard let r = Range(m.range, in: attr),
                      let n = Int(ns.substring(with: m.range(at: 1))),
                      n >= 1, n <= sources.count else { continue }
                attr[r].link = URL(string: "gwen-source://\(n)")
                attr[r].foregroundColor = Color.blue
            }
        }
        Self.mdCache.setObject(AttrBox(attr), forKey: key, cost: text.utf8.count * 4)
        return Text(attr)
    }

    static let footnoteRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,2})\\]")

    private var footnoteOpener: OpenURLAction {
        OpenURLAction { url in
            guard url.scheme == "gwen-source",
                  let n = Int(url.host ?? ""), n >= 1, n <= sources.count else {
                return .systemAction
            }
            openSource(sources[n - 1])
            return .handled
        }
    }

    private var bubbleColor: Color {
        isUser ? Color.blue : Color(.systemGray5)
    }

    private func saveAttachment(_ att: Attachment) {
        guard let media else { return }
        if let img = media.cachedImage(for: att) { saveToPhotos(img); return }
        Task { @MainActor in
            let img = await Task.detached(priority: .userInitiated) {
                media.loadUIImage(att, maxPixel: ImagePolicy.photoExportMaxPixel)
            }.value
            if let img { saveToPhotos(img) }
        }
    }

    private func saveToPhotos(_ img: UIImage) {
        let okMsg = L.t("image_saved")
        let failMsg = L.t("save_failed")
        let img = img
        let binding = $savedNote
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    binding.wrappedValue = success ? okMsg : failMsg
                }
            }
        }
    }
}