import GwenMobileKit
import Foundation

enum Formatters {
    private static let cache = LockedValue([String: DateFormatter]())
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
    static func eventChip(_ date: Date) -> String { render(date, locale: L.lang.locale, pattern: L.calChipFormat) }
    static func eventDateTime(_ date: Date) -> String { render(date, locale: posix, pattern: eventPattern) }
    static func stamp(_ date: Date) -> String { render(date, locale: posix, pattern: "yyyy-MM-dd") }

    static func eventDate(from text: String) -> Date? {
        parse(text, locale: posix, pattern: eventPattern)
    }

    static func eventDay(from text: String) -> Date? {
        parse(text, locale: posix, pattern: "yyyy-MM-dd")
    }

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func isoDate(from text: String) -> Date? {
        isoFormatter.date(from: text) ?? isoFractionalFormatter.date(from: text)
    }

    static let eventPattern = "yyyy-MM-dd HH:mm"
    static func planNow(_ date: Date) -> String { render(date, locale: posix, pattern: "yyyy-MM-dd HH:mm EEEE") }
    static func fileStamp(_ date: Date) -> String { render(date, locale: posix, pattern: "yyyy-MM-dd-HHmmss") }
    static func systemDate(_ date: Date) -> String { render(date, locale: british, pattern: "EEEE, yyyy-MM-dd") }
    static func systemTime(_ date: Date) -> String { render(date, locale: posix, pattern: "HH:mm") }

    static func price(_ value: Double, currency: String?) -> String {
        let code = currency.flatMap { $0.isEmpty ? nil : $0 } ?? L.lang.currencyCode
        return value.formatted(.currency(code: code).locale(L.lang.locale).precision(.fractionLength(0...2)))
    }

    static func countText(_ amount: Int) -> String {
        amount.formatted(.number.locale(L.lang.locale))
    }

    private static func render(_ date: Date, locale: Locale, pattern: String) -> String {
        formatted(locale: locale, pattern: pattern) { $0.string(from: date) }
    }

    private static func parse(_ text: String, locale: Locale, pattern: String) -> Date? {
        formatted(locale: locale, pattern: pattern) { $0.date(from: text) }
    }

    private static func formatted<Value>(locale: Locale, pattern: String,
                                         _ body: (DateFormatter) -> Value) -> Value {
        let formatter = cache.mutate { stored -> DateFormatter in
            let key = "\(locale.identifier)|\(pattern)"
            if let found = stored[key] { return found }
            let made = makeFormatter(locale: locale, pattern: pattern)
            stored[key] = made
            return made
        }
        return body(formatter)
    }

    private static func makeFormatter(locale: Locale, pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        return formatter
    }
}
