import SwiftUI

@MainActor
struct StatusLevelBadge: View {
    let level: AppStatusReport.Level
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 20

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: side * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch level {
        case .ok: return "checkmark"
        case .attention: return "exclamationmark"
        case .problem: return "xmark"
        case .neutral: return "info"
        }
    }

    private var tint: Color {
        switch level {
        case .ok: return Color(.systemGreen)
        case .attention: return Color(.systemOrange)
        case .problem: return Color(.systemRed)
        case .neutral: return Color(.systemGray)
        }
    }
}
