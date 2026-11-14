import SwiftUI

struct SourceReportView: View {
    let report: WebSourceReport

    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false

    private let initialIssueLimit = 6

    private struct ReasonCount: Identifiable {
        let reason: String
        let count: Int

        var id: String { reason }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    reasonSummary
                    issueList
                    Text(verbatim: L.t("source_report_note"))
                        .scaledFont(11)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: TapProbe.action({ dismiss() })) {
                        Text(verbatim: L.t("source_report_done"))
                            .scaledFont(13, weight: .semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L.t("source_report_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: TapProbe.action({ dismiss() })) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L.t("done"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !report.sourceIssues.isEmpty {
                Text(verbatim: report.sourceIssues.count == 1
                     ? L.fmt("source_report_summary_one", String(report.requested))
                     : L.fmt2("source_report_summary_many", String(report.sourceIssues.count),
                              String(report.requested)))
                    .scaledFont(14, weight: .semibold)
            }
            if !report.searchIssues.isEmpty {
                Text(verbatim: L.counted(report.searchIssues.count,
                                         one: "source_report_search_summary_one",
                                         many: "source_report_search_summary_many"))
                    .scaledFont(12)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder private var reasonSummary: some View {
        if report.issues.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reasonCounts) { item in
                        Text(verbatim: "\(item.reason) · \(item.count)")
                            .scaledFont(9.5, weight: .semibold)
                            .foregroundStyle(Color(.systemOrange))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(.systemOrange).opacity(0.12)))
                    }
                }
            }
        }
    }

    private var reasonCounts: [ReasonCount] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for issue in report.issues {
            if counts[issue.reason] == nil { order.append(issue.reason) }
            counts[issue.reason, default: 0] += 1
        }
        return order.map { ReasonCount(reason: $0, count: counts[$0] ?? 0) }
    }

    private var visibleIssues: [WebSourceIssue] {
        guard !expanded, report.issues.count > initialIssueLimit else { return report.issues }
        return Array(report.issues.prefix(initialIssueLimit))
    }

    private var hiddenIssueCount: Int {
        max(0, report.issues.count - initialIssueLimit)
    }

    @ViewBuilder private var issueList: some View {
        LazyVStack(spacing: 8) {
            ForEach(visibleIssues, id: \.self) { issue in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: symbol(issue.kind))
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(color(issue.kind))
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: domainLabel(issue))
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(Color(.label))
                        Text(verbatim: kindLabel(issue.kind))
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(color(issue.kind))
                        Text(verbatim: issue.reason)
                            .scaledFont(10.5)
                            .foregroundStyle(Color(.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            }
            if report.issues.count > initialIssueLimit {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }) {
                    Text(verbatim: expanded
                         ? L.t("source_report_show_less")
                         : L.fmt("source_report_show_more", String(hiddenIssueCount)))
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func domainLabel(_ issue: WebSourceIssue) -> String {
        issue.kind == .search ? L.t("source_report_search_domain") : issue.domain
    }

    private func kindLabel(_ kind: WebSourceIssue.Kind) -> String {
        switch kind {
        case .blocked: return L.t("source_report_kind_blocked")
        case .unavailable: return L.t("source_report_kind_unavailable")
        case .search: return L.t("source_report_kind_search")
        }
    }

    private func symbol(_ kind: WebSourceIssue.Kind) -> String {
        switch kind {
        case .blocked: return "hand.raised.fill"
        case .unavailable: return "wifi.exclamationmark"
        case .search: return "magnifyingglass"
        }
    }

    private func color(_ kind: WebSourceIssue.Kind) -> Color {
        switch kind {
        case .blocked: return Color(.systemOrange)
        case .unavailable: return Color(.secondaryLabel)
        case .search: return Color(.systemOrange)
        }
    }
}
