@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

extension SettingsView {
    var researchSection: some View {
        Section {
            Toggle(isOn: $settings.research.verifySources) {
                Label(L.t("research_verify_sources"), systemImage: "checkmark.seal")
            }
        } header: {
            Text(L.t("research"))
        } footer: {
            Text(L.t("research_verify_sources_footer"))
        }
    }
}
