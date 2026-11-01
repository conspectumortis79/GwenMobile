@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct ProviderSelectionView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(ProviderCatalog.all, id: \.id) { descriptor in
                    ProviderChoiceRow(descriptor: descriptor,
                                      selected: settings.provider == descriptor.id,
                                      choose: TapProbe.action {
                        AppSettings.flushKeySave()
                        settings.provider = descriptor.id
                        dismiss()
                    })
                }
            } header: {
                Text(L.t("provider_section"))
            } footer: {
                Text(L.t("provider_footer"))
            }
        }
        .navigationTitle(L.t("provider_section"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
