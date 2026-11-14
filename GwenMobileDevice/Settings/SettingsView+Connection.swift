import GwenMobileKit
import SwiftUI

extension SettingsView {
    var connectionSection: some View {
        Section {
            ProviderFormView(settings: settings)
        } header: {
            Text(verbatim: settings.descriptor.title)
        } footer: {
            ProviderFooterView(settings: settings)
        }
    }

    @ViewBuilder var balanceSection: some View {
        if settings.descriptor is any AccountBalanceReporting {
            remoteBalanceSection
        } else if settings.provider == .qwenCloud, let link = QwenCloudDescriptor.billingLink {
            Section {
                ProviderConsoleBalanceCard(descriptor: settings.descriptor, consoleURL: link)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(L.t("balance"))
            } footer: {
                Text(L.t("balance_console_footer"))
            }
        }
    }

    @ViewBuilder private var remoteBalanceSection: some View {
        Section {
            ProviderBalanceCard(
                descriptor: settings.descriptor,
                balance: balance,
                error: balanceError,
                updatedAt: balanceUpdatedAt,
                loading: balanceLoading,
                canRefresh: !balanceKey(for: settings.provider).isEmpty,
                refresh: TapProbe.action({
                    Task { await refreshCurrentBalance() }
                })
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text(L.t("balance"))
        } footer: {
            Text(L.t("balance_footer"))
        }
        .task(id: balanceReloadKey) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await loadBalanceForSettings()
        }
        if settings.provider == .openRouter {
            openRouterManagementSection
        }
    }

    @ViewBuilder private var openRouterManagementSection: some View {
        Section {
            SecureKeyRow(
                title: L.t("openrouter_management_key"),
                placeholder: "sk-or-…",
                key: Binding(get: { openRouterManagementKey.key },
                             set: { openRouterManagementKey.set($0) }),
                hasStoredKey: openRouterManagementKey.hasStoredKey,
                onClear: { openRouterManagementKey.clear() }
            )
            if let problem = openRouterManagementKey.problem {
                Text(problem).font(.footnote).foregroundStyle(Color.red)
            }
            Button(L.t("balance_refresh"), action: TapProbe.action({
                Task { await refreshCurrentBalance() }
            }))
            .disabled(openRouterManagementKey.key.isEmpty || balanceLoading)
        } header: {
            Text(L.t("openrouter_management_section"))
        } footer: {
            VStack(alignment: .leading, spacing: 5) {
                Text(L.t("openrouter_management_hint"))
                if let link = OpenRouterDescriptor.managementKeyLink {
                    Link(L.t("openrouter_management_link"), destination: link)
                }
            }
        }
    }

    @MainActor private var balanceReloadKey: String {
        let provider = settings.provider
        return "\(provider.rawValue)|\(settings.baseURL(for: provider))|\(balanceKey(for: provider))"
    }

    @MainActor func balanceKey(for provider: ProviderID) -> String {
        if provider == .openRouter, !openRouterManagementKey.key.isEmpty {
            return openRouterManagementKey.key
        }
        return settings.key(for: provider)
    }

    @MainActor func loadBalanceForSettings() async {
        resetBalance()
        let provider = settings.provider
        let key = balanceKey(for: provider)
        guard provider.descriptor is any AccountBalanceReporting, !key.isEmpty else { return }
        await refreshBalance(provider: provider, key: key)
    }

    @MainActor func refreshCurrentBalance() async {
        if settings.provider == .openRouter { openRouterManagementKey.flush() }
        await refreshBalance(provider: settings.provider, key: balanceKey(for: settings.provider))
    }

    @MainActor func resetBalance() {
        balanceRequest += 1
        balance = nil
        balanceError = nil
        balanceUpdatedAt = nil
        balanceLoading = false
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
            await refreshBalance(provider: provider, key: balanceKey(for: provider))
        } catch {
            let e = L.friendlyError(error.localizedDescription, model: settings.chatModel)
            testResult = "✖ " + e.message + (e.detail.isEmpty ? "" : " (\(e.detail))")
        }
    }

    @MainActor func refreshBalance(provider: ProviderID, key: String) async {
        guard let reporter = provider.descriptor as? any AccountBalanceReporting, !key.isEmpty else { return }
        balanceRequest += 1
        let request = balanceRequest
        balanceLoading = true
        balanceError = nil
        defer {
            if balanceRequest == request { balanceLoading = false }
        }
        do {
            let fresh = try await reporter.accountBalance(key: key)
            guard !Task.isCancelled, balanceRequest == request, settings.provider == provider else { return }
            balance = fresh
            balanceUpdatedAt = Date()
        } catch {
            guard !Task.isCancelled, balanceRequest == request, settings.provider == provider else { return }
            let status = (error as? APIError)?.status
            balanceError = L.friendlyError(error.localizedDescription, status: status).message
        }
    }
}
