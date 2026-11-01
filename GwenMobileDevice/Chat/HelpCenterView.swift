@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
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
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onUseExample: (String) -> Void
    var onOpenSettings: (() -> Void)? = nil

    @State private var query = ""
    @State private var category: HelpCategory = .all
    @State private var picked: HelpExample?
    @State private var showStatus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                        .padding(.top, 4)
                    topicsSection
                        .padding(.top, 16)
                    examplesSection
                        .padding(.top, 24)
                    quickAccessSection
                        .padding(.top, 26)
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
            .safeAreaInset(edge: .bottom) {
                if let picked { pickedBar(picked) }
            }
            .sheet(isPresented: $showStatus) {
                HelpStatusView(store: store, settings: settings)
            }
            .onChange(of: query) { _, value in
                guard !value.trimmed.isEmpty else { return }
                category = .all
                picked = nil
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
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("help_topics_section"))
                        .font(.title3.weight(.bold))
                    Text(L.t("help_topics_note"))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if category != .all || !query.trimmed.isEmpty {
                    Button(L.t("help_all"), action: TapProbe.action({ resetFilters() }))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 10)
            LazyVGrid(columns: topicColumns, spacing: 9) {
                ForEach(HelpCategory.allCases.filter { $0 != .all }) { item in
                    topicTile(item)
                }
            }
        }
    }

    private var topicColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 9),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private func topicTile(_ item: HelpCategory) -> some View {
        let selected = category == item
        let count = HelpCatalog.sections.first { $0.category == item }?.examples.count ?? 0
        return Button(action: TapProbe.action({
            category = selected ? .all : item
            query = ""
            picked = nil
        })) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(item.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L.counted(count, one: "help_example_count_one", many: "help_example_count"))
                        .font(.caption2)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [selected ? Color.accentColor.opacity(0.07) : Color(.secondarySystemGroupedBackground),
                                 Color(.secondarySystemGroupedBackground)],
                        startPoint: .top,
                        endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var examplesSection: some View {
        let sections = filteredSections
        let total = sections.reduce(0) { $0 + $1.examples.count }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("help_examples_section"))
                        .font(.title3.weight(.bold))
                    Text(examplesNote)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 8)
                Text(L.counted(total, one: "help_example_count_one", many: "help_example_count"))
                    .font(.footnote)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .fixedSize()
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 10)
            if sections.isEmpty {
                noResults
                    .padding(.top, 2)
            } else {
                ForEach(sections) { section in
                    sectionGroup(section)
                }
            }
        }
    }

    private var examplesNote: String {
        if !query.trimmed.isEmpty { return L.t("help_examples_results") }
        return category == .all ? L.t("help_examples_grouped") : L.t("help_examples_filtered")
    }

    private func sectionGroup(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.category.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer(minLength: 8)
                Text("\(section.examples.count)")
                    .font(.footnote)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 4)
            .padding(.top, 13)
            .padding(.bottom, 7)
            VStack(spacing: 0) {
                ForEach(section.examples) { example in
                    exampleRow(example, category: section.category)
                    if example.id != section.examples.last?.id {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let hintKey = section.hintKey {
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

    private func exampleRow(_ example: HelpExample, category: HelpCategory) -> some View {
        let selected = picked?.id == example.id
        return Button(action: TapProbe.action({ picked = selected ? nil : example })) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(category.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(example.detail)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t("help_quick_access"))
                .font(.title3.weight(.bold))
                .padding(.horizontal, 2)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                quickAccessRow(symbol: "checkmark.seal.fill",
                               tint: .green,
                               title: L.t("help_status_button"),
                               detail: L.t("help_status_detail")) {
                    showStatus = true
                }
                if let onOpenSettings {
                    Divider()
                        .padding(.leading, 52)
                    quickAccessRow(symbol: "gearshape.fill",
                                   tint: .gray,
                                   title: L.t("help_settings_button"),
                                   detail: L.t("help_settings_detail")) {
                        onOpenSettings()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func quickAccessRow(symbol: String, tint: Color, title: String, detail: String,
                                action: @escaping @MainActor () -> Void) -> some View {
        Button(action: TapProbe.action({ action() })) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func pickedBar(_ example: HelpExample) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("help_picked_label"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .textCase(.uppercase)
                    Text(example.title)
                        .font(.footnote)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(L.t("help_use_example")) {
                    onUseExample(example.text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                Button(action: TapProbe.action({ picked = nil })) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("help_clear_selection"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private func clearSearch() {
        query = ""
        category = .all
        picked = nil
    }

    private func resetFilters() {
        query = ""
        category = .all
        picked = nil
    }

    private var filteredSections: [HelpSection] {
        HelpCatalog.filtered(category: category, query: query)
    }
}

@MainActor
struct HelpStatusView: View {
    let store: ChatStore
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var report: AppStatusReport?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(report.rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 9) {
                                    Text(AppStatusReport.symbol(row.level))
                                        .font(.subheadline)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.label)
                                            .font(.subheadline.weight(.semibold))
                                        Text(row.value)
                                            .font(.caption)
                                            .foregroundStyle(Color(.secondaryLabel))
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(11)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground)))
                            }
                            Text("\(AppStatusReport.symbol(report.summaryLevel)) \(report.summary)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 4)
                            Text(L.t("app_status_footer_local"))
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        .padding(16)
                    }
                } else {
                    ProgressView(L.t("app_status_working"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L.t("app_status_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done"), action: TapProbe.action({ dismiss() }))
                }
            }
            .task {
                if report == nil {
                    report = await AppStatusReader(store: store, settings: settings).read()
                }
            }
        }
        .windowAppearance()
    }
}
