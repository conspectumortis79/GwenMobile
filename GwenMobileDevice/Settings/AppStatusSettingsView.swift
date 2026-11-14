import GwenMobileKit
import SwiftUI

@MainActor
struct AppStatusSettingsView: View {
    let store: ChatStore
    @ObservedObject var settings: AppSettings
    @State private var report: AppStatusReport?
    @State private var checking = false

    var body: some View {
        Section {
            if let report {
                ForEach(Array(report.rows.enumerated()), id: \.offset) { _, row in
                    statusRow(row)
                }
                summaryRow(report)
                SettingsBusyButton(title: L.t("app_status_refresh"),
                                   busyTitle: L.t("app_status_working"),
                                   busy: checking,
                                   symbol: "arrow.clockwise",
                                   enabled: true,
                                   action: TapProbe.action({ reload() }))
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L.t("app_status_working"))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        } header: {
            Text(L.t("help_status_button"))
        } footer: {
            Text(L.t("app_status_footer_local"))
        }
        .task {
            guard report == nil else { return }
            await check()
        }
    }

    private func statusRow(_ row: AppStatusReport.Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatusLevelBadge(level: row.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.subheadline.weight(.semibold))
                Text(row.value)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ report: AppStatusReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatusLevelBadge(level: report.summaryLevel)
            Text(report.summary)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func reload() {
        guard !checking else { return }
        Task { await check() }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        report = await AppStatusReader(store: store, settings: settings).read()
    }
}
