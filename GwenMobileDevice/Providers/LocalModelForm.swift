@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct LocalModelForm: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = LocalModelStore.shared

    @State private var tab: Tab = .installed
    @State private var openModel: String?
    @State private var deleting: LocalModelChoice?
    @State private var problem: String?
    @State private var query = ""
    @State private var onlyFitting = true
    @State private var onlyVision = false
    @State private var onlyTools = false
    @State private var searched = false
    @State private var loadedID: String?

    enum Tab: String, CaseIterable, Identifiable {
        case installed
        case discover
        case storage

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .installed: return "local_tab_installed"
            case .discover: return "local_tab_discover"
            case .storage: return "local_tab_storage"
            }
        }
    }

    var body: some View {
        Group {
            tabPicker
            switch tab {
            case .installed: installedSection
            case .discover: discoverSections
            case .storage: storageSections
            }
        }
        .task {
            store.refresh()
            await refreshLoaded()
        }
        .task(id: tab) {
            await refreshLoaded()
            if tab == .discover { await searchIfNeeded() }
        }
        .alert(L.t("local_model_delete_title"), isPresented: deleteBinding, presenting: deleting) { choice in
            Button(L.t("local_model_delete"), role: .destructive) { delete(choice) }
            Button(L.t("local_model_cancel"), role: .cancel) {}
        } message: { choice in
            Text(verbatim: L.fmt("local_model_delete_message", choice.name))
        }
    }

    private var installed: [LocalModelChoice] {
        let list = store.installedChoices()
        guard let activeID = active?.id else {
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return list.sorted { lhs, rhs in
            if lhs.id == activeID { return true }
            if rhs.id == activeID { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var active: LocalModelChoice? {
        store.choice(for: settings.profile(of: .local).chatModel)
    }

    private var usedBytes: Int64 {
        installed.reduce(0) { $0 + $1.bytes }
    }

    private var filtered: [LocalModelChoice] {
        store.huggingFace.filter { choice in
            guard !store.isInstalled(choice) else { return false }
            if onlyFitting && !canDownload(choice) { return false }
            if onlyVision && !choice.vision { return false }
            if onlyTools && !choice.tools { return false }
            guard !query.isEmpty else { return true }
            return choice.name.localizedCaseInsensitiveContains(query)
                || choice.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var tabPicker: some View {
        Section {
            Picker(L.t("local_tab_installed"), selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(L.t(item.titleKey)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        Section {
            if installed.isEmpty {
                Text(L.t("local_installed_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L.t("local_tab_discover")) { tab = .discover }
            } else {
                ForEach(installed) { choice in
                    installedRow(choice)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("local_installed_footer"))
                if let problem {
                    Text(verbatim: problem).foregroundStyle(Color.red)
                }
            }
        }
    }

    @ViewBuilder
    private var discoverSections: some View {
        Section {
            searchRow
            filtersRow
        }
        Section {
            if store.huggingFaceLoading && store.huggingFace.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("local_model_hf_loading"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if filtered.isEmpty {
                Text(L.t(onlyFitting ? "local_model_hf_empty" : "local_discover_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { choice in
                    discoverRow(choice)
                }
            }
            if let error = store.huggingFaceError {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            Button {
                searched = true
                Task { await store.searchHuggingFace() }
            } label: {
                Label(store.huggingFaceLoading ? L.t("local_model_hf_loading")
                                              : L.t("local_model_hf_search"),
                      systemImage: "arrow.clockwise")
            }
            .disabled(store.huggingFaceLoading)
        } header: {
            Text(L.t("local_model_hf_section"))
        } footer: {
            Text(L.t("local_model_hf_hint"))
        }
    }

    @ViewBuilder
    private var storageSections: some View {
        Section {
            if installed.isEmpty {
                Text(L.t("local_installed_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: L.fmt("local_storage_used", size(usedBytes)))
                        .font(.headline)
                    Text(L.t("local_storage_models"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    storageBar
                }
                .padding(.vertical, 4)
                ForEach(installed) { choice in
                    storageRow(choice)
                }
            }
        } header: {
            Text(L.t("local_tab_storage"))
        } footer: {
            if let problem {
                Text(verbatim: problem).foregroundStyle(Color.red)
            }
        }
        Section {
            LabeledContent(L.t("local_model_storage")) {
                Text(verbatim: size(store.freeBytes))
            }
            LabeledContent(L.t("local_model_memory")) {
                Text(verbatim: store.memoryLabel)
            }
            if loadedID != nil {
                Button(role: .destructive) {
                    Task { await unload() }
                } label: {
                    Text(L.t("local_model_unload"))
                }
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField(L.t("local_discover_search"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filtersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(L.t("local_filter_fits"), isOn: $onlyFitting)
                chip(L.t("local_model_capability_vision"), isOn: $onlyVision)
                chip(L.t("local_model_capability_tools"), isOn: $onlyTools)
            }
        }
    }

    private var storageBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(installed) { choice in
                    Capsule(style: .continuous)
                        .fill(accent(choice))
                        .frame(width: barWidth(choice, in: proxy.size.width))
                }
            }
        }
        .frame(height: 9)
        .background(Color(.systemGray5), in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private func modelSummary(_ choice: LocalModelChoice) -> some View {
        badge(choice)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: choice.name)
                .font(.subheadline.weight(.medium))
            Text(verbatim: factLine(choice))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
    }

    private func installedRow(_ choice: LocalModelChoice) -> some View {
        HStack(spacing: 12) {
            modelSummary(choice)
            if active?.id == choice.id {
                pill(L.t("local_model_active_short"), color: .green)
            } else {
                Button(L.t("local_model_use_short")) { activate(choice) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            modelMenu(choice)
        }
    }

    private func storageRow(_ choice: LocalModelChoice) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent(choice))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: choice.name)
                    .font(.subheadline)
                Text(L.t(choice.id == active?.id ? "local_model_active_short" : "local_model_installed"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(verbatim: size(choice.bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
            if choice.id != active?.id {
                Button(role: .destructive) {
                    deleting = choice
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func discoverRow(_ choice: LocalModelChoice) -> some View {
        let status = store.status(for: choice)
        let open = openModel == choice.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    toggle(choice)
                } label: {
                    HStack(spacing: 12) {
                        modelSummary(choice)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                discoverTrailing(choice, status: status, open: open)
            }
            if status.phase.isDownloading {
                downloadProgress(choice, status: status)
            } else if case .failed(let message) = status.phase {
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if open {
                discoverDetails(choice)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func discoverTrailing(_ choice: LocalModelChoice, status: LocalModelStatus,
                                  open: Bool) -> some View {
        if status.phase.isDownloading {
            Text(verbatim: "\(Int(status.fraction * 100)) %")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else if !canDownload(choice) {
            pill(L.t("local_model_too_large_badge"), color: .orange)
        } else if open {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else {
            Button {
                Task { await download(choice) }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L.t("local_model_download")))
        }
    }

    @ViewBuilder
    private func discoverDetails(_ choice: LocalModelChoice) -> some View {
        HStack(spacing: 8) {
            fact(L.t("local_model_size"), size(choice.bytes))
            fact(L.t("local_model_ram"), "≥ \(choice.minRamGB) GB")
            if let context = contextLabel(choice) {
                fact(L.t("local_model_context"), context)
            }
        }
        if canDownload(choice) {
            Button(L.t("local_model_download")) {
                Task { await download(choice) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Text(verbatim: L.fmt2("local_model_memory_warning", choice.name,
                                  String(choice.minRamGB)))
                .font(.footnote)
                .foregroundStyle(Color.orange)
        }
    }

    private func downloadProgress(_ choice: LocalModelChoice, status: LocalModelStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: status.fraction)
            HStack(spacing: 8) {
                Text(verbatim: "\(Int(status.fraction * 100)) %")
                Text(verbatim: "\(size(status.received)) / \(size(status.total))")
                Spacer(minLength: 8)
                Button(L.t("local_model_cancel"), role: .cancel) { store.cancel(choice.id) }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Text(L.t("local_model_keep_open"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func modelMenu(_ choice: LocalModelChoice) -> some View {
        Menu {
            if active?.id != choice.id {
                Button {
                    activate(choice)
                } label: {
                    Label(L.t("local_model_use_short"), systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                deleting = choice
            } label: {
                Label(L.t("local_model_delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
    }

    private func chip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn.wrappedValue ? Color(.systemBackground) : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? Color.primary : Color(.systemGray5), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ choice: LocalModelChoice) -> some View {
        Text(verbatim: glyph(choice))
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .background(accent(choice), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func barWidth(_ choice: LocalModelChoice, in total: CGFloat) -> CGFloat {
        guard usedBytes > 0 else { return 0 }
        let gaps = CGFloat(max(0, installed.count - 1)) * 2
        return max(0, (total - gaps) * CGFloat(choice.bytes) / CGFloat(usedBytes))
    }

    private func factLine(_ choice: LocalModelChoice) -> String {
        var parts = [size(choice.bytes)]
        if let context = contextLabel(choice) { parts.append(context) }
        parts.append(choice.vision ? L.t("local_model_capability_vision")
                                   : L.t("local_model_capability_text"))
        return parts.joined(separator: " · ")
    }

    private func contextLabel(_ choice: LocalModelChoice) -> String? {
        let context = choice.context.trimmingCharacters(in: .whitespaces)
        guard !context.isEmpty, context != "-" else { return nil }
        return context
    }

    private func toggle(_ choice: LocalModelChoice) {
        withAnimation(.easeInOut(duration: 0.15)) {
            openModel = openModel == choice.id ? nil : choice.id
        }
    }

    private func canDownload(_ choice: LocalModelChoice) -> Bool {
        LocalMemory.canHost(choice.bytes)
    }

    private func activate(_ choice: LocalModelChoice) {
        settings.updateProfile(of: .local) { profile in
            profile.chatModel = choice.id
            if choice.vision { profile.visionModel = choice.id }
            if !profile.availableModels.contains(choice.id) {
                profile.availableModels.append(choice.id)
            }
        }
    }

    private func download(_ choice: LocalModelChoice) async {
        problem = nil
        await store.download(choice)
        guard case .installed = store.status(for: choice).phase else { return }
        await reload()
        activate(choice)
        openModel = nil
        tab = .installed
        await refreshLoaded()
    }

    private func delete(_ choice: LocalModelChoice) {
        problem = nil
        guard store.delete(choice) else {
            deleting = nil
            problem = L.t("local_model_delete_error")
            return
        }
        settings.forgetDeletedModel(choice.id, of: .local)
        if loadedID == choice.id {
            loadedID = nil
            Task { await LocalEngine.shared.unload() }
        }
        deleting = nil
        openModel = openModel == choice.id ? nil : openModel
        Task { await reload() }
    }

    private func unload() async {
        await LocalEngine.shared.unload()
        loadedID = nil
    }

    private func refreshLoaded() async {
        loadedID = await LocalEngine.shared.modelSnapshot().loaded
    }

    private func searchIfNeeded() async {
        guard !searched, !store.huggingFaceLoading else { return }
        searched = true
        await store.searchHuggingFace()
    }

    private func reload() async {
        do {
            try await settings.reloadModels(of: .local)
        } catch {
            problem = L.t("local_model_reload_error") + " " + error.localizedDescription
        }
    }

    private func glyph(_ choice: LocalModelChoice) -> String {
        if choice.source == .huggingFace { return "HF" }
        return choice.family == .qwen ? "Q3" : "G4"
    }

    private func accent(_ choice: LocalModelChoice) -> Color {
        if choice.source == .huggingFace { return Color.blue }
        return choice.family == .qwen ? Color.indigo : Color.green
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
