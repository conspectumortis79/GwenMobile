import Foundation

struct BriefingSettings: Equatable, Codable {
    var enabled = false
    var minutes = AppSettings.defaultBriefingMinutes
    var weather = true
    var reminders = true
    var birthdays = true
    var travel = true

    var time: Date {
        get { time(in: .current) }
        set { minutes = Self.minutes(of: newValue) }
    }

    func time(in calendar: Calendar, now: Date = Date()) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return calendar.date(from: parts) ?? calendar.startOfDay(for: now)
    }

    static func minutes(of time: Date, in calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var includes: DayBriefingIncludes {
        DayBriefingIncludes(weather: weather, reminders: reminders,
                            birthdays: birthdays, travel: travel)
    }

    static func load(from defaults: UserDefaults = .standard) -> BriefingSettings {
        var settings = BriefingSettings()
        settings.enabled = SettingsDefaults.bool(defaults, SettingsKey.briefingEnabled, false)
        settings.minutes = SettingsDefaults.int(defaults, SettingsKey.briefingMinutes,
                                                AppSettings.defaultBriefingMinutes)
        settings.weather = SettingsDefaults.bool(defaults, SettingsKey.briefingWeather, true)
        settings.reminders = SettingsDefaults.bool(defaults, SettingsKey.briefingReminders, true)
        settings.birthdays = SettingsDefaults.bool(defaults, SettingsKey.briefingBirthdays, true)
        settings.travel = SettingsDefaults.bool(defaults, SettingsKey.briefingTravel, true)
        return settings.normalized
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: SettingsKey.briefingEnabled)
        defaults.set(minutes, forKey: SettingsKey.briefingMinutes)
        defaults.set(weather, forKey: SettingsKey.briefingWeather)
        defaults.set(reminders, forKey: SettingsKey.briefingReminders)
        defaults.set(birthdays, forKey: SettingsKey.briefingBirthdays)
        defaults.set(travel, forKey: SettingsKey.briefingTravel)
    }

    var normalized: BriefingSettings {
        var settings = self
        settings.minutes = min(max(minutes, 0), 23 * 60 + 59)
        return settings
    }
}
