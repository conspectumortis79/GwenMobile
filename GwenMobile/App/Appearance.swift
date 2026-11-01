import GwenMobileKit
import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case light
    case dark

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .light: return "appearance_light"
        case .dark: return "appearance_dark"
        }
    }

    nonisolated var label: String { L.t(labelKey) }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    nonisolated var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    nonisolated static func persisted(defaults: UserDefaults) -> AppAppearance {
        AppAppearance(rawValue: defaults.string(forKey: SettingsKey.appearance) ?? "") ?? .light
    }
}

@MainActor
struct WindowAppearance: ViewModifier {
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content.preferredColorScheme(settings.appearance.colorScheme)
            .onAppear { sync() }
            .onChange(of: settings.appearance) { _, _ in sync() }
    }

    private func sync() {
        WindowStyleSync.apply(settings.appearance.interfaceStyle)
    }
}

extension View {
    @MainActor func windowAppearance() -> some View {
        modifier(WindowAppearance())
    }
}
