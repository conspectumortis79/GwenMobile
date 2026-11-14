import SwiftUI

struct ProviderBalanceCard: View {
    let descriptor: any ProviderDescriptor
    let balance: ProviderBalance?
    let error: String?
    let updatedAt: Date?
    let loading: Bool
    let canRefresh: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            amountArea
            if let detailText {
                Text(verbatim: detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let noteText {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(verbatim: noteText)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(.systemRed))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemRed).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
            }
            footer
        }
        .padding(16)
        .background(ProviderCardBackground(glyph: descriptor.glyph))
    }

    private var header: some View {
        ProviderHeaderRow(glyph: descriptor.glyph, title: descriptor.title,
                          caption: L.t("balance_source")) {
            refreshButton
        }
    }

    private var amountArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            if balance?.status == .usageOnly {
                Text(L.t("balance_used"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 10) {
                amountText
                Spacer(minLength: 8)
                statusPill
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder private var amountText: some View {
        if let primary = balance?.entries.first {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: primary.total)
                    .scaledFont(30, weight: .semibold, relativeTo: .title)
                    .monospacedDigit()
                Text(verbatim: primary.currency)
                    .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(verbatim: "—")
                .scaledFont(30, weight: .semibold, relativeTo: .title)
                .foregroundStyle(.secondary)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)
            Text(verbatim: statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(statusTint.opacity(0.12), in: Capsule())
        .foregroundStyle(statusTint)
        .fixedSize()
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            ZStack {
                Circle().fill(Color(.tertiarySystemFill))
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.accentColor)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(!canRefresh || loading)
        .opacity(canRefresh ? 1 : 0.45)
        .accessibilityLabel(L.t("balance_refresh"))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 13)
            HStack(spacing: 8) {
                if let updatedAt {
                    Text(L.fmt("balance_checked", Formatters.time(updatedAt)))
                } else {
                    Text(L.t("balance_pending"))
                }
                Spacer(minLength: 8)
                if let link = manageLink {
                    Link(destination: link) {
                        Text(verbatim: manageTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 9)
        }
    }

    private var detailText: String? {
        guard let balance, let primary = balance.entries.first else { return nil }
        var parts: [String] = []
        if let purchased = balance.purchasedCredits, let used = balance.usedCredits {
            parts.append(L.fmt2("balance_credit_usage", money(purchased), money(used)))
        } else if balance.status == .usageOnly {
            if let usage = balance.usage {
                parts.append(L.fmt("balance_usage_only", money(usage)))
            }
        } else {
            if let granted = primary.granted {
                parts.append(L.fmt("balance_granted", money(granted, currency: primary.currency)))
            }
            if let toppedUp = primary.toppedUp {
                parts.append(L.fmt("balance_topped_up", money(toppedUp, currency: primary.currency)))
            }
            if let limit = balance.limit, let usage = balance.usage {
                parts.append(L.fmt2("balance_limit_usage", money(limit), money(usage)))
            }
        }
        let extra = balance.entries.dropFirst().map { money($0.total, currency: $0.currency) }
        if !extra.isEmpty {
            parts.append(extra.joined(separator: " · "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var noteText: String? {
        if let error { return error }
        if balance?.status == .unavailable { return L.t("balance_unavailable_note") }
        return nil
    }

    private var displayStatus: DisplayStatus {
        if loading { return .loading }
        if error != nil { return .error }
        guard let balance else { return .pending }
        switch balance.status {
        case .available: return .available
        case .unavailable: return .unavailable
        case .usageOnly: return .usageOnly
        }
    }

    private var statusText: String {
        switch displayStatus {
        case .available: return L.t("balance_status_available")
        case .unavailable: return L.t("balance_status_unavailable")
        case .usageOnly: return L.t("balance_status_usage_only")
        case .error: return L.t("balance_status_error")
        case .loading: return L.t("balance_status_loading")
        case .pending: return L.t("balance_pending")
        }
    }

    private var statusTint: Color {
        switch displayStatus {
        case .available: return Color(.systemGreen)
        case .unavailable, .error: return Color(.systemRed)
        case .usageOnly, .loading, .pending: return Color(.systemGray)
        }
    }

    private var manageLink: URL? {
        if descriptor.id == .openRouter, let link = OpenRouterDescriptor.creditsLink { return link }
        if descriptor.id == .deepSeek, let link = DeepSeekDescriptor.usageLink { return link }
        return descriptor.consoleLink
    }

    private var manageTitle: String {
        descriptor.id == .deepSeek ? L.t("balance_usage_open") : L.t("balance_manage")
    }

    private func money(_ value: String, currency: String = "$") -> String {
        currency == "$" ? "\(value) $" : "\(value) \(currency)"
    }

    private enum DisplayStatus {
        case pending
        case loading
        case available
        case unavailable
        case usageOnly
        case error
    }
}
