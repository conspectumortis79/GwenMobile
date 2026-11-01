@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

@MainActor
struct DeleteAllConfirmation: ViewModifier {
    @ObservedObject var cleaner: HistoryCleaner
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(L.t("delete_all_title"), isPresented: $isPresented) {
            Button(L.t("delete_all"), role: .destructive, action: TapProbe.action({ cleaner.deleteAllConversations() }))
            Button(L.t("cancel"), role: .cancel, action: TapProbe.action({}))
        } message: {
            Text(verbatim: cleaner.usage.deleteAllBody)
        }
    }
}

extension View {
    @MainActor func deleteAllConfirmation(cleaner: HistoryCleaner,
                                          isPresented: Binding<Bool>) -> some View {
        modifier(DeleteAllConfirmation(cleaner: cleaner, isPresented: isPresented))
    }
}
