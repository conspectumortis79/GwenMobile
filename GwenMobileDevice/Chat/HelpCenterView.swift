import GwenMobileKit
import SwiftUI

@MainActor
final class HelpRequests: ObservableObject {
    static let shared = HelpRequests()

    @Published private(set) var token = 0

    func ask() {
        flowMark("HILFE angefragt")
        token += 1
    }
}

enum HelpCategory: String, CaseIterable, Identifiable {
    case all
    case chat
    case pictures
    case files
    case day
    case media
    case language
    case prices
    case voice

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .all: return "help_all"
        case .chat: return "help_cat_chat"
        case .pictures: return "help_cat_pictures"
        case .files: return "help_cat_files"
        case .day: return "help_cat_day"
        case .media: return "help_cat_media"
        case .language: return "help_cat_language"
        case .prices: return "help_cat_prices"
        case .voice: return "help_cat_voice"
        }
    }
    var title: String { L.t(titleKey) }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .chat: return "sparkles"
        case .pictures: return "photo"
        case .files: return "doc.text"
        case .day: return "calendar"
        case .media: return "music.note"
        case .language: return "character.bubble"
        case .prices: return "eurosign.circle"
        case .voice: return "waveform"
        }
    }
    var tint: Color {
        switch self {
        case .all: return .blue
        case .chat: return .indigo
        case .pictures: return .purple
        case .files: return .teal
        case .day: return .red
        case .media: return .pink
        case .language: return .blue
        case .prices: return .green
        case .voice: return .orange
        }
    }
}

struct HelpExample: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let detailKey: String
    let symbol: String

    var title: String { L.t(titleKey) }
    var detail: String { L.t(detailKey) }
    var text: String { title }
}

struct HelpSection: Identifiable {
    let category: HelpCategory
    let examples: [HelpExample]
    let hintKey: String?

    var id: String { category.rawValue }
}

enum HelpCatalog {
    static let sections: [HelpSection] = [
        HelpSection(category: .chat, examples: [
            HelpExample(id: "chat_1", titleKey: "help_example_chat_1",
                        detailKey: "help_example_chat_1_detail", symbol: "sparkles"),
            HelpExample(id: "chat_2", titleKey: "help_example_chat_2",
                        detailKey: "help_example_chat_2_detail", symbol: "text.bubble"),
        ], hintKey: nil),
        HelpSection(category: .pictures, examples: [
            HelpExample(id: "pictures_1", titleKey: "help_example_pictures_1",
                        detailKey: "help_example_pictures_1_detail", symbol: "paintbrush.pointed"),
            HelpExample(id: "pictures_2", titleKey: "help_example_pictures_2",
                        detailKey: "help_example_pictures_2_detail", symbol: "photo.on.rectangle.angled"),
            HelpExample(id: "pictures_3", titleKey: "help_example_pictures_3",
                        detailKey: "help_example_pictures_3_detail", symbol: "circle.lefthalf.filled"),
        ], hintKey: "help_hint_attachments"),
        HelpSection(category: .files, examples: [
            HelpExample(id: "files_1", titleKey: "help_example_files_1",
                        detailKey: "help_example_files_1_detail", symbol: "doc.text"),
            HelpExample(id: "files_2", titleKey: "help_example_files_2",
                        detailKey: "help_example_files_2_detail", symbol: "doc.viewfinder"),
        ], hintKey: nil),
        HelpSection(category: .day, examples: [
            HelpExample(id: "day_1", titleKey: "help_example_day_1",
                        detailKey: "help_example_day_1_detail", symbol: "calendar"),
            HelpExample(id: "day_2", titleKey: "help_example_day_2",
                        detailKey: "help_example_day_2_detail", symbol: "calendar.badge.plus"),
            HelpExample(id: "day_3", titleKey: "help_example_day_3",
                        detailKey: "help_example_day_3_detail", symbol: "bell.badge"),
        ], hintKey: nil),
        HelpSection(category: .media, examples: [
            HelpExample(id: "media_1", titleKey: "help_example_media_1",
                        detailKey: "help_example_media_1_detail", symbol: "music.note"),
            HelpExample(id: "media_2", titleKey: "help_example_media_2",
                        detailKey: "help_example_media_2_detail", symbol: "phone.fill"),
        ], hintKey: nil),
        HelpSection(category: .language, examples: [
            HelpExample(id: "language_1", titleKey: "help_example_language_1",
                        detailKey: "help_example_language_1_detail", symbol: "character.bubble"),
            HelpExample(id: "language_2", titleKey: "help_example_language_2",
                        detailKey: "help_example_language_2_detail", symbol: "speaker.wave.2"),
        ], hintKey: nil),
        HelpSection(category: .prices, examples: [
            HelpExample(id: "prices_1", titleKey: "help_example_prices_1",
                        detailKey: "help_example_prices_1_detail", symbol: "eurosign.circle"),
            HelpExample(id: "prices_2", titleKey: "help_example_prices_2",
                        detailKey: "help_example_prices_2_detail", symbol: "tag"),
        ], hintKey: nil),
        HelpSection(category: .voice, examples: [
            HelpExample(id: "voice_1", titleKey: "help_example_voice_1",
                        detailKey: "help_example_voice_1_detail", symbol: "waveform"),
            HelpExample(id: "voice_2", titleKey: "help_example_voice_2",
                        detailKey: "help_example_voice_2_detail", symbol: "speaker.wave.2.fill"),
        ], hintKey: "help_hint_voice"),
    ]

    static func filtered(category: HelpCategory, query: String) -> [HelpSection] {
        let needle = query.trimmed.lowercased()
        return sections.compactMap { section in
            guard category == .all || section.category == category else { return nil }
            let examples = section.examples.filter { example in
                needle.isEmpty
                    || example.title.lowercased().contains(needle)
                    || example.detail.lowercased().contains(needle)
                    || section.category.title.lowercased().contains(needle)
            }
            guard !examples.isEmpty || needle.isEmpty else { return nil }
            return HelpSection(category: section.category, examples: examples, hintKey: section.hintKey)
        }
    }
}

@MainActor
struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    let onUseExample: (String) -> Void

    @State private var query = ""
    @State private var category: HelpCategory = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                        .padding(.top, 8)
                    topicsSection
                        .padding(.top, 16)
                    examplesSection
                        .padding(.top, 18)
                    Text(L.t("help_intro_body"))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L.t("help_attach_row"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done"), action: TapProbe.action({ dismiss() }))
                        .accessibilityLabel(L.t("help_close"))
                }
            }
            .onChange(of: query) { _, value in
                guard !value.trimmed.isEmpty else { return }
                category = .all
            }
        }
        .windowAppearance()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(.secondaryLabel))
            TextField(L.t("help_search_placeholder"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button(action: TapProbe.action({ clearSearch() })) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("help_clear_search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill)))
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("help_topics_section"))
                    .font(.title3)
                    .foregroundStyle(Color(.secondaryLabel))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if category != .all || !query.trimmed.isEmpty {
                    Button(L.t("help_all"), action: TapProbe.action({ resetFilters() }))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                } else {
                    Text("\(HelpCatalog.sections.count)")
                        .font(.subheadline)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(HelpCatalog.sections) { section in
                    topicRow(section)
                    if section.id != HelpCatalog.sections.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(cardShape.fill(Color(.secondarySystemGroupedBackground)))
            .clipShape(cardShape)
            Text(L.t("help_topics_note"))
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private func topicRow(_ section: HelpSection) -> some View {
        let selected = category == section.category
        return Button(action: TapProbe.action({
            category = selected ? .all : section.category
            query = ""
        })) {
            HStack(spacing: 12) {
                Image(systemName: section.category.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(section.category.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.category.title)
                        .foregroundStyle(Color.primary)
                    Text(L.counted(section.examples.count, one: "help_example_count_one",
                                   many: "help_example_count"))
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var examplesSection: some View {
        let examples = filteredExamples
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("help_examples_section"))
                    .font(.title3)
                    .foregroundStyle(Color(.secondaryLabel))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(examples.count)")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
            if let note = examplesNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
            }
            if examples.isEmpty {
                noResults
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(examples) { example in
                        exampleRow(example)
                        if example.id != examples.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(cardShape.fill(Color(.secondarySystemGroupedBackground)))
                .clipShape(cardShape)
            }
            if let hintKey = filteredHintKey {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text(L.t(hintKey))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
        }
    }

    private var examplesNote: String? {
        if !query.trimmed.isEmpty { return L.t("help_examples_results") }
        if category != .all { return L.t("help_examples_filtered") }
        return nil
    }

    private func exampleRow(_ example: HelpExample) -> some View {
        Button(action: TapProbe.action({
            onUseExample(example.text)
            dismiss()
        })) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: example.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.title)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(example.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(L.t("help_use_example"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color(.tertiaryLabel))
            Text(L.t("help_no_results"))
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func clearSearch() {
        query = ""
        category = .all
    }

    private func resetFilters() {
        query = ""
        category = .all
    }

    private var filteredExamples: [HelpExample] {
        filteredSections.flatMap(\.examples)
    }

    private var filteredHintKey: String? {
        guard query.trimmed.isEmpty, category != .all else { return nil }
        return HelpCatalog.sections.first { $0.category == category }?.hintKey
    }

    private var filteredSections: [HelpSection] {
        HelpCatalog.filtered(category: category, query: query)
    }
}
