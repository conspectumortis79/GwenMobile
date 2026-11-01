@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

enum FileGlyph {
    static func label(for kind: FileKind) -> String {
        switch kind {
        case .pdf: return "PDF"
        case .rtf: return "RTF"
        case .docx: return "DOCX"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .text: return "TXT"
        case .video: return "VIDEO"
        }
    }

    static func tint(for kind: FileKind) -> (Color, Color) {
        switch kind {
        case .pdf: return (Color(.systemRed), Color(.systemRed).opacity(0.12))
        case .rtf: return (Color(.systemOrange), Color(.systemOrange).opacity(0.12))
        case .docx: return (Color(.systemIndigo), Color(.systemIndigo).opacity(0.12))
        case .csv: return (Color(.systemGreen), Color(.systemGreen).opacity(0.12))
        case .json: return (Color(.systemPurple), Color(.systemPurple).opacity(0.12))
        case .text: return (Color(.systemBlue), Color(.systemBlue).opacity(0.12))
        case .video: return (Color(.systemRed), Color(.systemRed).opacity(0.12))
        }
    }
}

struct FileBadge: View {
    let kind: FileKind

    var body: some View {
        Text(verbatim: FileGlyph.label(for: kind))
            .scaledFont(9, weight: .heavy)
            .foregroundStyle(FileGlyph.tint(for: kind).0)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(FileGlyph.tint(for: kind).1))
    }
}

private let fileCardPadding = EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)

private struct FileCardSurface: ViewModifier {
    enum Width {
        case fixed(CGFloat)
        case upTo(CGFloat)
    }

    let width: Width

    @ViewBuilder func body(content: Content) -> some View {
        switch width {
        case .fixed(let value):
            content.padding(fileCardPadding).frame(width: value, alignment: .leading).background(board)
        case .upTo(let value):
            content.padding(fileCardPadding).frame(maxWidth: value, alignment: .leading).background(board)
        }
    }

    private var board: some View {
        RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator), lineWidth: 0.7))
    }
}

private extension View {
    func fileCardSurface(_ width: FileCardSurface.Width) -> some View {
        modifier(FileCardSurface(width: width))
    }

    func fileCardTitle() -> some View {
        font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1)
    }

    func fileCardMeta() -> some View {
        font(.system(size: 10)).foregroundStyle(Color(.secondaryLabel)).lineLimit(2)
    }
}

struct PendingFileCard: View {
    let pending: PendingFile
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                FileBadge(kind: pending.kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: pending.name)
                        .fileCardTitle()
                    if pending.reading {
                        HStack(spacing: 5) {
                            Text(L.t("file_reading")).scaledFont(10)
                                .foregroundStyle(Color(.secondaryLabel))
                            ProcessingDots()
                                .scaleEffect(0.6)
                        }
                    } else {
                        Text(verbatim: pending.failed ? L.t("file_no_text") : pending.attached.metaText)
                            .fileCardMeta()
                    }
                }
            }
            .fileCardSurface(.fixed(186))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, Color(.systemGray3))
            }
            .accessibilityLabel(L.t("attach_remove"))
            .padding(3)
        }
    }
}

struct OcrFileCard: View {
    let entry: OcrFile
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .scaledFont(13)
                    .foregroundStyle(Color(.systemGreen))
                Text(verbatim: "\(entry.displayName) · \(entry.metaText)")
                    .scaledFont(11, weight: .semibold)
                    .lineLimit(1)
                    .foregroundStyle(Color(.secondaryLabel))
                Image(systemName: "square.and.arrow.up")
                    .scaledFont(11, weight: .bold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("ocr_send_file"))
    }
}

struct StoredFileCard: View {
    let file: AttachedFile
    var onOpen: () -> Void
    var onShare: (() -> Void)? = nil

    init(file: AttachedFile, onOpen: @escaping () -> Void, onShare: (() -> Void)? = nil) {
        self.file = file
        self.onOpen = onOpen
        self.onShare = onShare
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                cardBody
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("open_file"))
            if let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("scan_share_action"))
            }
        }
    }

    private var cardBody: some View {
        HStack(spacing: 8) {
            FileBadge(kind: file.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: file.name)
                    .fileCardTitle()
                Text(verbatim: file.metaText)
                    .fileCardMeta()
            }
        }
        .fileCardSurface(.upTo(236))
    }
}
