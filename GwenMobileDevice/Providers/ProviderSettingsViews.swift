@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

extension Color {
    init(_ glyph: ProviderGlyph) {
        self.init(red: glyph.red, green: glyph.green, blue: glyph.blue)
    }
}

extension AppSettings {
    func keyBinding(for provider: ProviderID) -> Binding<String> {
        Binding(get: { self.key(for: provider) }, set: { self.setKey($0, for: provider) })
    }
}

struct ProviderGlyphView: View {
    let glyph: ProviderGlyph

    var body: some View {
        Text(verbatim: glyph.text)
            .scaledFont(13, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color(glyph), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ProviderChoiceRow: View {
    let descriptor: any ProviderDescriptor
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                ProviderGlyphView(glyph: descriptor.glyph)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: descriptor.title)
                        .foregroundStyle(Color(.label))
                    Text(verbatim: descriptor.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CapabilityChip: View {
    let feature: ProviderFeature
    let availability: FeatureAvailability

    private var dot: Color {
        switch availability {
        case .available: return .green
        case .probed: return .orange
        case .unavailable: return Color(.systemGray3)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(L.t(feature.labelKey))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(.systemGray5), in: Capsule())
        .accessibilityLabel(Text(verbatim: "\(L.t(feature.labelKey)): \(L.t(availability.labelKey))"))
    }
}

struct CapabilityChipsRow: View {
    let capabilities: ProviderCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("features"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProviderFeature.allCases) { feature in
                        CapabilityChip(feature: feature, availability: capabilities[feature])
                    }
                }
            }
        }
    }
}

struct SecureKeyRow: View {
    let placeholder: String
    @Binding var key: String
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(L.t("api_key"))
            SecureField(placeholder, text: $key)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !key.isEmpty {
                Button(L.t("key_clear"), action: onClear)
            }
        }
    }
}

struct StackedTextField: View {
    let title: String
    let placeholder: String
    let monospaced: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(monospaced ? .footnote.monospaced() : .body)
        }
    }
}

@MainActor
struct ProviderFormView: View {
    @ObservedObject var settings: AppSettings
    let balance: String?

    var body: some View {
        switch settings.provider {
        case .qwenCloud: QwenCloudForm(settings: settings)
        case .openAICompatible: OpenAICompatibleForm(settings: settings)
        case .local: LocalModelForm(settings: settings)
        case .openRouter: OpenRouterForm(settings: settings, balance: balance)
        case .deepSeek: DeepSeekForm(settings: settings, balance: balance)
        }
        CapabilityChipsRow(capabilities: settings.capabilities)
    }
}

@MainActor
struct QwenCloudForm: View {
    @ObservedObject var settings: AppSettings

    private var key: Binding<String> { settings.keyBinding(for: .qwenCloud) }

    var body: some View {
        Picker(L.t("billing"), selection: $settings.connections.qwenCloud.billing) {
            ForEach(QwenBilling.allCases) { Text(verbatim: $0.label).tag($0) }
        }
        if settings.connections.qwenCloud.showsRegion {
            Picker(L.t("region"), selection: $settings.connections.qwenCloud.region) {
                ForEach(QwenRegion.allCases) { Text(verbatim: $0.label).tag($0) }
            }
        }
        if settings.connections.qwenCloud.showsWorkspace {
            StackedTextField(title: L.t("workspace_id"), placeholder: L.t("workspace_placeholder"),
                             monospaced: true, text: $settings.connections.qwenCloud.workspace)
        }
        SecureKeyRow(placeholder: settings.descriptor.keyPlaceholder(settings.connections),
                     key: key, onClear: { settings.clearKey(for: .qwenCloud) })
    }
}

@MainActor
struct OpenAICompatibleForm: View {
    @ObservedObject var settings: AppSettings

    private var key: Binding<String> { settings.keyBinding(for: .openAICompatible) }

    private var preset: Binding<String> {
        Binding(get: { settings.connections.openAICompatible.preset },
                set: { settings.connections.openAICompatible.select(presetID: $0) })
    }

    private var baseURL: Binding<String> {
        Binding(get: { settings.connections.openAICompatible.baseURL },
                set: { settings.connections.openAICompatible.edit(baseURL: $0) })
    }

    var body: some View {
        Picker(L.t("preset"), selection: preset) {
            ForEach(OpenAIPresets.all) { Text(verbatim: $0.label).tag($0.id) }
        }
        StackedTextField(title: L.t("base_url"), placeholder: "https://…/v1", monospaced: true, text: baseURL)
        SecureKeyRow(placeholder: settings.descriptor.keyPlaceholder(settings.connections),
                     key: key, onClear: { settings.clearKey(for: .openAICompatible) })
    }
}

@MainActor
struct OpenRouterForm: View {
    @ObservedObject var settings: AppSettings
    let balance: String?

    private var key: Binding<String> { settings.keyBinding(for: .openRouter) }

    var body: some View {
        SecureKeyRow(placeholder: settings.descriptor.keyPlaceholder(settings.connections),
                     key: key, onClear: { settings.clearKey(for: .openRouter) })
        StackedTextField(title: L.t("app_name_optional"), placeholder: "GwenMobile",
                         monospaced: false, text: $settings.connections.openRouter.appName)
        BalanceRow(balance: balance)
    }
}

@MainActor
struct DeepSeekForm: View {
    @ObservedObject var settings: AppSettings
    let balance: String?

    private var key: Binding<String> { settings.keyBinding(for: .deepSeek) }

    var body: some View {
        SecureKeyRow(placeholder: settings.descriptor.keyPlaceholder(settings.connections),
                     key: key, onClear: { settings.clearKey(for: .deepSeek) })
        BalanceRow(balance: balance)
    }
}

@MainActor
private struct BalanceRow: View {
    let balance: String?

    var body: some View {
        LabeledContent(L.t("balance")) {
            Text(verbatim: balance ?? L.t("balance_pending"))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct ProviderFooterView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let link = settings.descriptor.consoleLink {
                Link(settings.descriptor.consoleLinkTitle, destination: link)
            }
            Text(verbatim: settings.descriptor.footer)
            Text(verbatim: settings.baseURL)
                .font(.footnote.monospaced())
            if let problem = settings.keychainProblem {
                Text(problem).foregroundStyle(Color.red)
            }
        }
    }
}
