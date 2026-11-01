@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

extension SettingsView {
    var filesSection: some View {
        Section {
            Toggle(isOn: $settings.autoOCR) {
                Text(L.t("ocr_auto")).scaledFont(15)
            }
        } header: {
            Text(L.t("storage_files"))
        } footer: {
            Text(L.t("ocr_footer"))
        }
    }

    var priceWatchSection: some View {
        Section {
            Button(action: TapProbe.action({
                showPriceWatch = true
            })) {
                HStack {
                    Label(L.t("price_watch_settings_row"), systemImage: "tag")
                    Spacer(minLength: 6)
                    Text(priceWatchCountLabel)
                        .foregroundStyle(Color(.secondaryLabel))
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .foregroundStyle(Color.primary)
        } footer: {
            Text(L.t("price_watch_settings_footer"))
        }
    }

    var priceWatchCountLabel: String {
        Self.priceWatchCountLabel(priceWatchCount)
    }

    static func priceWatchCountLabel(_ count: Int) -> String {
        L.counted(count, one: "price_watch_count_one", many: "price_watch_count_many")
    }

    var memorySection: some View {
        Section {
            Toggle(L.t("memory_toggle"), isOn: $settings.memory.enabled)
            Button(action: TapProbe.action({
                showMemory = true
            })) {
                HStack {
                    Label(L.t("memory_about_row"), systemImage: "person.crop.circle")
                    Spacer()
                    Text(memoryCountLabel)
                        .foregroundStyle(Color(.secondaryLabel))
                    Image(systemName: "chevron.right")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .foregroundStyle(Color.primary)
            Toggle(L.t("memory_suggestions_toggle"), isOn: $settings.memory.suggestions)
            Toggle(L.t("memory_chips_toggle"), isOn: $settings.memory.chips)
            Picker(L.t("memory_retention"), selection: $settings.memory.retention) {
                ForEach(MemoryRetention.allCases) { option in
                    Text(L.t(option.labelKey)).tag(option)
                }
            }
            Button(role: .destructive, action: TapProbe.action({
                confirmDeleteMemory = true
            })) {
                Label(L.t("memory_delete_all"), systemImage: "trash")
            }
            .disabled(memoryCount == 0)
            .confirmationDialog(L.t("memory_delete_all"), isPresented: $confirmDeleteMemory,
                                titleVisibility: .visible) {
                Button(L.t("memory_delete_all_confirm"), role: .destructive, action: TapProbe.action({
                    Task {
                        await store.memory.deleteAll()
                        memoryCount = 0
                    }
                }))
                Button(L.t("cancel"), role: .cancel, action: TapProbe.action({}))
            }
        } header: {
            Text(L.t("memory_settings_head"))
        } footer: {
            Text(L.t("memory_settings_footer"))
        }
    }

    var memoryCountLabel: String {
        Self.memoryCountLabel(memoryCount)
    }

    static func memoryCountLabel(_ count: Int) -> String {
        L.counted(count, one: "memory_count_one", many: "memory_count_many")
    }

    var storageSection: some View {
        Section {
            usageRow(L.t("storage_images"), "photo", usageDetail)
            if cleaner.usage.documentFiles > 0 {
                usageRow(L.t("storage_files"), "doc.text", cleaner.usage.documentsLine)
            }
            if cleaner.usage.exportFiles > 0 {
                usageRow(L.t("storage_exports"), "square.and.arrow.up", cleaner.usage.exportsLine)
            }
            usageRow(L.t("storage_history"), "text.bubble", historyDetail)
            Button(role: .destructive, action: TapProbe.action({ confirmDeleteAll = true })) {
                Label(L.t("delete_all"), systemImage: "trash")
            }
            .disabled(cleaner.usage.conversations < 1)
        } header: {
            Text(L.t("storage"))
        } footer: {
            Text(L.t("fresh_start_note"))
        }
    }

    func usageRow(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(Color(.secondaryLabel))
        }
    }

    var usageDetail: String { cleaner.usage.imagesLine }

    var historyDetail: String { cleaner.usage.historyLine }
}
