@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

@MainActor
struct SettingsCategoryView: View {
    let owner: SettingsView
    let category: SettingsCategory
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            owner.categorySections(category)
        }
        .id(settings.language)
        .environment(\.locale, settings.language.locale)
        .navigationTitle(L.t(category.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                owner.doneButton
            }
        }
    }
}
