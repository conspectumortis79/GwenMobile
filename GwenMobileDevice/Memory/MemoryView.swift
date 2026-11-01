@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct MemoryView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var entries: [MemoryEntry] = []
    @State private var search = ""
    @State private var editor: MemoryEditorTarget?
    @State private var exportFailure: String?
    @State private var undo: UndoItem?

    var body: some View {
        List {
            if entries.isEmpty {
                Text(L.t("memory_empty"))
                    .foregroundStyle(Color(.secondaryLabel))
            } else {
                ForEach(MemoryCategory.allCases) { category in
                    let items = filtered.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(L.t(category.labelKey)) {
                            ForEach(items) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: L.t("memory_search_placeholder"))
        .sheetToolbar(L.t("memory_view_title"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let undo {
                UndoToast(title: L.t("memory_undo_title"),
                          detail: undo.entry.text,
                          onUndo: { restore(undo) },
                          onExpire: { if self.undo?.id == undo.id { self.undo = nil } })
                    .id(undo.id)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: undo?.id)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: TapProbe.action({
                    editor = MemoryEditorTarget(id: "new", entry: nil)
                })) {
                    Label(L.t("memory_add"), systemImage: "plus")
                }
                .accessibilityLabel(L.t("memory_add"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: TapProbe.action({
                    export()
                })) {
                    Label(L.t("memory_export"), systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(L.t("memory_export"))
            }
        }
        .task { await reload() }
        .sheet(item: $editor) { target in
            MemoryEditorSheet(entry: target.entry)
                .environmentObject(store)
        }
        .onChange(of: editor?.id) { _, target in
            guard target == nil else { return }
            Task { await reload() }
        }
        .alert(L.t("memory_export"), isPresented: Binding(get: { exportFailure != nil },
                                                        set: { if !$0 { exportFailure = nil } })) {
            Button(L.t("ok"), action: TapProbe.action({ exportFailure = nil }))
        } message: {
            Text(exportFailure ?? "")
        }
    }

    private struct UndoItem: Identifiable {
        let id = UUID()
        let entry: MemoryEntry
        let index: Int
    }

    static func filtered(_ entries: [MemoryEntry], search: String) -> [MemoryEntry] {
        let needle = search.trimmed.lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.text.lowercased().contains(needle) }
    }

    private var filtered: [MemoryEntry] {
        Self.filtered(entries, search: search)
    }

    private func row(_ entry: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.category.symbol)
                .foregroundStyle(MemoryStyle.tint(entry.category))
                .scaledFont(14, weight: .semibold)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .scaledFont(15)
                Text(meta(entry))
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 6)
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .scaledFont(11)
                    .foregroundStyle(Color(.systemOrange))
                    .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: TapProbe.action({ editor = MemoryEditorTarget(id: entry.shortKey, entry: entry) }))
        .contextMenu { menu(entry) }
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: TapProbe.action({ delete(entry) })) {
                Label(L.t("memory_delete"), systemImage: "trash")
            }
            Button(action: TapProbe.action({ togglePin(entry) })) {
                Label(entry.pinned ? L.t("memory_unpin") : L.t("memory_pin"),
                      systemImage: entry.pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func menu(_ entry: MemoryEntry) -> some View {
        Button(action: TapProbe.action({ editor = MemoryEditorTarget(id: entry.shortKey, entry: entry) })) {
            Label(L.t("memory_edit"), systemImage: "pencil")
        }
        Button(action: TapProbe.action({ togglePin(entry) })) {
            Label(entry.pinned ? L.t("memory_unpin") : L.t("memory_pin"),
                  systemImage: entry.pinned ? "pin.slash" : "pin")
        }
        Divider()
        Button(role: .destructive, action: TapProbe.action({ delete(entry) })) {
            Label(L.t("memory_delete"), systemImage: "trash")
        }
    }

    @discardableResult
    static func remove(entry: MemoryEntry, store: ChatStore) async -> Int? {
        await store.memory.delete(key: entry.shortKey)
    }

    static func togglePin(entry: MemoryEntry, store: ChatStore) async {
        await store.memory.setPinned(key: entry.shortKey, pinned: !entry.pinned)
    }

    private func togglePin(_ entry: MemoryEntry) {
        Task {
            await Self.togglePin(entry: entry, store: store)
            await reload()
        }
    }

    private func delete(_ entry: MemoryEntry) {
        Task {
            guard let index = await Self.remove(entry: entry, store: store) else { return }
            await reload()
            undo = UndoItem(entry: entry, index: index)
        }
    }

    private func restore(_ item: UndoItem) {
        undo = nil
        Task {
            await store.memory.restore(item.entry, at: item.index)
            await reload()
        }
    }

    private func meta(_ entry: MemoryEntry) -> String {
        var parts = [L.t(entry.source.labelKey), L.fmt("memory_used_times", String(entry.useCount))]
        if let due = MemoryStore.dueText(entry) {
            parts.append(L.fmt("memory_due_line", due))
            if entry.remind { parts.append(L.t("memory_reminder_planned")) }
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        entries = await store.memory.all()
    }

    static func exportURL(for data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwenmobile-gedaechtnis.json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func export() {
        Task {
            let data = await store.memory.exportData()
            do {
                let url = try Self.exportURL(for: data)
                try Presenter.share(url: url)
            } catch {
                exportFailure = L.t("export_unavailable")
            }
        }
    }
}

struct MemoryEditorTarget: Identifiable {
    let id: String
    var entry: MemoryEntry?
}

enum MemoryStyle {
    static func tint(_ category: MemoryCategory) -> Color {
        switch category {
        case .person: return Color(.systemBlue)
        case .likes: return Color(.systemPink)
        case .people: return Color(.systemOrange)
        case .work: return Color(.systemIndigo)
        case .health: return Color(.systemGreen)
        case .plans: return Color(.systemTeal)
        }
    }
}

@MainActor
struct MemoryEditorSheet: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let entry: MemoryEntry?
    @State private var text = ""
    @State private var category: MemoryCategory = .person
    @State private var pinned = false
    @State private var remind = false

    static func commit(store: ChatStore, entry: MemoryEntry?, text: String, category: MemoryCategory,
                       pinned: Bool, remind: Bool) async {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        if remind, entry?.dueDate != nil { MemoryNotifier.prepare() }
        if let entry {
            await store.memory.update(key: entry.shortKey, text: clean, category: category,
                                      pinned: pinned, remind: remind)
        } else if let added = await store.memory.add(text: clean, category: category, source: .manual) {
            if pinned { await store.memory.setPinned(key: added.entry.shortKey, pinned: true) }
        }
    }

    static func remove(store: ChatStore, entry: MemoryEntry?) async {
        guard let entry else { return }
        await store.memory.delete(key: entry.shortKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("memory_text_placeholder"), text: $text, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Picker(L.t("memory_category"), selection: $category) {
                        ForEach(MemoryCategory.allCases) { option in
                            Label(L.t(option.labelKey), systemImage: option.symbol).tag(option)
                        }
                    }
                    Toggle(L.t("memory_pinned"), isOn: $pinned)
                    if entry?.dueDate != nil {
                        Toggle(L.t("memory_reminder"), isOn: $remind)
                    }
                }
                if let due = entry.flatMap({ MemoryStore.dueText($0) }) {
                    Section {
                        Text(L.fmt("memory_due_line", due))
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                if entry != nil {
                    Section {
                        Button(role: .destructive, action: TapProbe.action({
                            delete()
                        })) {
                            Label(L.t("memory_delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? L.t("memory_new") : L.t("memory_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("cancel"), action: TapProbe.action({ dismiss() }))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("memory_save"), action: TapProbe.action({ save() }))
                        .disabled(text.trimmed.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    func load() {
        guard let entry else { return }
        text = entry.text
        category = entry.category
        pinned = entry.pinned
        remind = entry.remind
    }

    private func save() {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        let entry = entry
        let category = category
        let pinned = pinned
        let remind = remind
        Task {
            await Self.commit(store: store, entry: entry, text: clean, category: category,
                              pinned: pinned, remind: remind)
            dismiss()
        }
    }

    private func delete() {
        let entry = entry
        Task {
            await Self.remove(store: store, entry: entry)
            dismiss()
        }
    }
}
