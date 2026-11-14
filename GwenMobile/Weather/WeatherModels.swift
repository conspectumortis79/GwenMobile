import GwenMobileKit
import Foundation

enum WeatherKind: String, Codable, Sendable {
    case sun
    case partly
    case cloud
    case fog
    case drizzle
    case rain
    case heavyRain
    case snow
    case storm

    static func wmo(_ code: Int) -> WeatherKind {
        switch code {
        case 0: return .sun
        case 1, 2: return .partly
        case 3: return .cloud
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65: return .rain
        case 66, 67: return .heavyRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 80, 81, 82: return .rain
        case 95, 96, 99: return .storm
        default: return .cloud
        }
    }

    var symbol: String {
        switch self {
        case .sun: return "sun.max.fill"
        case .partly: return "cloud.sun.fill"
        case .cloud: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .snow: return "cloud.snow.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }

    var isStorm: Bool { self == .storm }
    var isHeavy: Bool { self == .heavyRain || self == .storm }
    var isWet: Bool { self == .rain || self == .heavyRain || self == .drizzle || self == .storm }
}

struct WeatherHour: Codable, Hashable, Sendable {
    var hour: Int
    var temp: Double
    var rain: Int
    var precip: Double
    var wind: Double
    var gust: Double
    var uv: Double
    var kind: WeatherKind

    enum CodingKeys: String, CodingKey {
        case hour, temp, rain, precip, wind, gust, uv, kind
    }

    init(hour: Int, temp: Double, rain: Int, precip: Double, wind: Double, gust: Double, uv: Double,
         kind: WeatherKind) {
        self.hour = hour
        self.temp = temp
        self.rain = rain
        self.precip = precip
        self.wind = wind
        self.gust = gust
        self.uv = uv
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        hour = try fields.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        temp = try fields.decodeIfPresent(Double.self, forKey: .temp) ?? 0
        rain = try fields.decodeIfPresent(Int.self, forKey: .rain) ?? 0
        precip = try fields.decodeIfPresent(Double.self, forKey: .precip) ?? 0
        wind = try fields.decodeIfPresent(Double.self, forKey: .wind) ?? 0
        gust = try fields.decodeIfPresent(Double.self, forKey: .gust) ?? 0
        uv = try fields.decodeIfPresent(Double.self, forKey: .uv) ?? 0
        kind = try fields.decodeIfPresent(WeatherKind.self, forKey: .kind) ?? .cloud
    }
}

struct WeatherPlace: Codable, Hashable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timezone: String?
}

struct WeatherRef: Codable, Hashable, Sendable {
    var place: String
    var latitude: Double
    var longitude: Double
    var day: String
    var timezone: String?
    var hours: [WeatherHour]

    enum CodingKeys: String, CodingKey {
        case place, latitude, longitude, day, timezone, hours
    }

    init(place: String, latitude: Double, longitude: Double, day: String,
         timezone: String?, hours: [WeatherHour]) {
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.day = day
        self.timezone = timezone
        self.hours = hours
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        place = try fields.decodeIfPresent(String.self, forKey: .place) ?? ""
        latitude = try fields.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try fields.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        day = try fields.decodeIfPresent(String.self, forKey: .day) ?? ""
        timezone = try fields.decodeIfPresent(String.self, forKey: .timezone)
        hours = try fields.decodeIfPresent([WeatherHour].self, forKey: .hours) ?? []
    }

    var isOpenable: Bool { !hours.isEmpty }

    var placeValue: WeatherPlace {
        WeatherPlace(name: place, latitude: latitude, longitude: longitude, timezone: timezone)
    }
}

struct WeatherRequest: Equatable, Sendable {
    typealias Day = DayChoice

    static let maxDayOffset = 366

    var place: String?
    var day: Day
    var date: String?
    var offset: Int? = nil

    static func from(_ args: [String: Any]) -> WeatherRequest {
        let day = Day.parse(args["day"] as? String)
        let place = ToolDecision.text(args, "place")
        let date = ToolDecision.text(args, "date")
        let raw = (args["dayOffset"] as? Int)
            ?? (args["dayOffset"] as? String).flatMap(Int.init)
        let offset = raw.map { min(max($0, -Self.maxDayOffset), Self.maxDayOffset) }
        return WeatherRequest(place: place, day: day, date: date, offset: offset)
    }

    var namesADay: Bool { date != nil || offset != nil }

    func daysAhead(from now: Date, calendar: Calendar) -> Int? {
        guard let raw = date, let parsed = Formatters.eventDay(from: raw) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: parsed)).day
    }
}
