import Foundation

enum Formatters {
    private static let cache = FormatterCache()
    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let british = Locale(identifier: "en_GB")

    static func time(_ date: Date) -> String { render(date, locale: L.lang.locale, pattern: L.timeFormat) }
    static func day(_ date: Date) -> String { render(date, locale: L.lang.locale, pattern: L.dayFormat) }

    static func relationalDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return L.t("today") }
        if calendar.isDateInYesterday(date) { return L.t("yesterday") }
        return day(date)
    }
    static func eventStart(_ date: Date) -> String { render(date, locale: L.lang.locale, pattern: L.calStartFormat) }
    static func eventDateTime(_ date: Date) -> String { render(date, locale: posix, pattern: eventPattern) }

    static func eventDate(from text: String) -> Date? {
        parse(text, locale: posix, pattern: eventPattern)
    }

    static let eventPattern = "yyyy-MM-dd HH:mm"
    static func planNow(_ date: Date) -> String { render(date, locale: posix, pattern: "yyyy-MM-dd HH:mm EEEE") }
    static func fileStamp(_ date: Date) -> String { render(date, locale: posix, pattern: "yyyy-MM-dd-HHmmss") }
    static func systemDate(_ date: Date) -> String { render(date, locale: british, pattern: "EEEE, yyyy-MM-dd") }

    private static func render(_ date: Date, locale: Locale, pattern: String) -> String {
        formatter(locale: locale, pattern: pattern).string(from: date)
    }

    private static func parse(_ text: String, locale: Locale, pattern: String) -> Date? {
        formatter(locale: locale, pattern: pattern).date(from: text)
    }

    private static func formatter(locale: Locale, pattern: String) -> DateFormatter {
        let key = "\(locale.identifier)|\(pattern)"
        if let hit = cache.formatter(for: key) { return hit }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        cache.setFormatter(formatter, for: key)
        return formatter
    }
}

final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(for key: String) -> DateFormatter? {
        lock.lock()
        defer { lock.unlock() }
        return formatters[key]
    }

    func setFormatter(_ formatter: DateFormatter, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        formatters[key] = formatter
    }
}
