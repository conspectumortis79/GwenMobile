@testable import GwenMobileFeatureCore
import GwenMobileKit
#if targetEnvironment(macCatalyst)
import SwiftUI

@MainActor
final class MacHelpRequests: ObservableObject {
    static let shared = MacHelpRequests()

    @Published private(set) var token = 0

    func open() {
        token += 1
    }
}

struct MacHelpView: View {
    static let sectionKeys = ["mac_help_start", "mac_help_chat", "mac_help_research",
                             "mac_help_pictures", "mac_help_docs"]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                sections
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .frame(minWidth: 420, idealWidth: 540, minHeight: 420, idealHeight: 600)
        .onAppear { flowMark("MAC hilfe angezeigt abschnitte=\(Self.sectionKeys.count)") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(verbatim: L.t("mac_help_title"))
                .scaledFont(17, weight: .semibold)
            Spacer(minLength: 12)
            Button(L.t("mac_help_close"), action: TapProbe.action({ dismiss() }))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: L.t("mac_help_intro"))
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
            section("mac_help_start_head", "mac_help_start_body")
            section("mac_help_chat_head", "mac_help_chat_body")
            section("mac_help_research_head", "mac_help_research_body")
            section("mac_help_pictures_head", "mac_help_pictures_body")
            shortcuts
            section("mac_help_docs_head", "mac_help_docs_body")
        }
    }

    private func section(_ head: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: L.t(head))
                .scaledFont(15, weight: .semibold)
            Text(verbatim: L.t(body))
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: L.t("mac_help_keys_head"))
                .scaledFont(15, weight: .semibold)
            Text(verbatim: L.t("mac_help_key_quit"))
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
            Text(verbatim: L.t("mac_help_key_help"))
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

struct MacHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(L.t("mac_help_menu"), action: TapProbe.action({ MacHelpRequests.shared.open() }))
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
#endif
