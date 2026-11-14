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
        let d = defaults
        var settings = BriefingSettings()
        settings.enabled = d.object(forKey: SettingsKey.briefingEnabled) as? Bool ?? false
        settings.minutes = d.object(forKey: SettingsKey.briefingMinutes) as? Int
            ?? AppSettings.defaultBriefingMinutes
        settings.weather = d.object(forKey: SettingsKey.briefingWeather) as? Bool ?? true
        settings.reminders = d.object(forKey: SettingsKey.briefingReminders) as? Bool ?? true
        settings.birthdays = d.object(forKey: SettingsKey.briefingBirthdays) as? Bool ?? true
        settings.travel = d.object(forKey: SettingsKey.briefingTravel) as? Bool ?? true
        return settings.normalized
    }

    func store(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(enabled, forKey: SettingsKey.briefingEnabled)
        d.set(minutes, forKey: SettingsKey.briefingMinutes)
        d.set(weather, forKey: SettingsKey.briefingWeather)
        d.set(reminders, forKey: SettingsKey.briefingReminders)
        d.set(birthdays, forKey: SettingsKey.briefingBirthdays)
        d.set(travel, forKey: SettingsKey.briefingTravel)
    }

    var normalized: BriefingSettings {
        var settings = self
        settings.minutes = min(max(minutes, 0), 23 * 60 + 59)
        return settings
    }
}
