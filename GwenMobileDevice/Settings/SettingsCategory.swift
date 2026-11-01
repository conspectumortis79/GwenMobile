@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case ai
    case voice
    case language
    case data
    case services
    case help

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .ai: return "settings_category_ai"
        case .voice: return "settings_category_voice"
        case .language: return "settings_category_language"
        case .data: return "settings_category_data"
        case .services: return "settings_category_services"
        case .help: return "settings_category_help"
        }
    }

    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .voice: return "waveform"
        case .language: return "globe"
        case .data: return "internaldrive"
        case .services: return "square.grid.2x2"
        case .help: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .ai: return .indigo
        case .voice: return .pink
        case .language: return .blue
        case .data: return .green
        case .services: return .orange
        case .help: return .teal
        }
    }
}

struct SettingsCategoryRow: View {
    let category: SettingsCategory
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(category.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(category.titleKey))
                    .foregroundStyle(Color.primary)
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("settings-category-\(category.rawValue)")
    }
}
