@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

extension SettingsView {
    var providerSection: some View {
        Section {
            ForEach(ProviderCatalog.all, id: \.id) { descriptor in
                ProviderChoiceRow(descriptor: descriptor, selected: settings.provider == descriptor.id,
                                  choose: TapProbe.action {
                    AppSettings.flushKeySave()
                    settings.provider = descriptor.id
                })
            }
        } header: {
            Text(L.t("provider_section"))
        } footer: {
            Text(L.t("provider_footer"))
        }
    }

    var connectionSection: some View {
        Section {
            ProviderFormView(settings: settings, balance: balance)
        } header: {
            Text(verbatim: settings.descriptor.title)
        } footer: {
            ProviderFooterView(settings: settings)
        }
    }

    func runConnectionTest() {
        testStream?.cancel()
        testStream = Task { await testConnection() }
    }

    func abandonConnectionTest() {
        testStream?.cancel()
        testStream = nil
    }

    @MainActor func testConnection() async {
        AppSettings.flushKeySave()
        testing = true
        testResult = nil
        defer { testing = false }
        let provider = settings.provider
        let key = settings.key(for: provider)
        let msg = ChatMessage(role: .user, text: L.t("test_prompt"))
        guard let req = try? QwenAPI.makeRequest(baseURL: settings.baseURL(for: provider), key: key,
                                                 model: settings.chatModel, messages: [msg],
                                                 imageData: [], stream: true,
                                                 thinking: settings.thinkingOffDirective(
                                                    for: settings.chatModel)) else {
            testResult = L.t("bad_url")
            return
        }
        do {
            let got = try await chatRunner(req, { _ in })
            testResult = got.trimmed.isEmpty
                ? L.t("connected_empty") : L.t("answered") + String(got.prefix(40))
            await refreshBalance(provider: provider, key: key)
        } catch {
            let e = L.friendlyError(error.localizedDescription, model: settings.chatModel)
            testResult = "✖ " + e.message + (e.detail.isEmpty ? "" : " (\(e.detail))")
        }
    }

    @MainActor func refreshBalance(provider: ProviderID, key: String) async {
        guard let reporter = provider.descriptor as? any AccountBalanceReporting else { return }
        let text = await reporter.accountBalance(key: key)
        guard settings.provider == provider else { return }
        balance = text
    }
}
