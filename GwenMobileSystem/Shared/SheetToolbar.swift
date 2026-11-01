@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

struct SheetToolbar: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: TapProbe.action({ dismiss() })) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L.t("cancel"))
                }
            }
    }
}

extension View {
    func sheetToolbar(_ title: String) -> some View { modifier(SheetToolbar(title: title)) }
}
