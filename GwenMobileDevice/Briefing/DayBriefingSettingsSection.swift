@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct DayBriefingSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            Toggle(L.t("brief_notify_toggle"), isOn: $settings.briefing.enabled)
                .onChange(of: settings.briefing.enabled) { _, on in
                    if on { DayBriefingNotifier.preparePermission() }
                    Task { await DayBriefingNotifier.refresh(force: true) }
                }
            if settings.briefing.enabled {
                DatePicker(L.t("brief_time"), selection: Binding(
                    get: { settings.briefing.time },
                    set: { settings.briefing.time = $0 }
                ), displayedComponents: .hourAndMinute)
            }
            Toggle(L.t("brief_include_weather"), isOn: $settings.briefing.weather)
            Toggle(L.t("brief_include_reminders"), isOn: $settings.briefing.reminders)
            Toggle(L.t("brief_include_birthdays"), isOn: $settings.briefing.birthdays)
            Toggle(L.t("brief_include_travel"), isOn: $settings.briefing.travel)
        } header: {
            Text(L.t("brief_settings"))
        } footer: {
            Text(L.t("brief_settings_footer"))
        }
        .onChange(of: settings.briefing.minutes) { _, _ in
            Task { await DayBriefingNotifier.refresh(force: true) }
        }
        .onChange(of: settings.briefing.includes) { _, _ in
            Task { await DayBriefingNotifier.refresh(force: true) }
        }
    }
}
