@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

final class WeatherDecodingTests: GwenTestCase {
    private let date = "2026-10-05"

    func testTheForecastKeepsTheHoursFromSixToTwentyTwo() throws {
        let place = WeatherPlace(name: "München", latitude: 48.137,
                                 longitude: 11.575, timezone: "Europe/Berlin")
        let ref = try XCTUnwrap(OpenMeteo.day(from: ForecastFixture.json(date: date, thunderAfternoon: true),
                                              date: date, place: place))
        XCTAssertEqual(ref.hours.count, 17)
        XCTAssertEqual(ref.hours.first?.hour, 6)
        XCTAssertEqual(ref.hours.last?.hour, 22)
        XCTAssertEqual(ref.timezone, "Europe/Berlin")
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 6 })?.temp, 6)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 15 })?.kind, .storm)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 9 })?.kind, .rain)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 12 })?.kind, .sun)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 12 })?.precip, 0.5)
    }

    func testTheLastForecastDaysWithNullValuesStillDecode() throws {
        let times = (0..<24).map { date + "T" + String(format: "%02d:00", $0) }
        let temperatures: [Any] = (0..<24).map { $0 >= 20 ? NSNull() as Any : Double($0) as Any }
        let probabilities: [Any] = (0..<24).map { _ in NSNull() }
        let winds: [Any] = (0..<24).map { _ in 12.0 }
        let gusts: [Any] = (0..<24).map { $0 == 10 ? NSNull() as Any : 30.0 as Any }
        let codes: [Any] = (0..<24).map { $0 == 11 ? NSNull() as Any : 3 as Any }
        let object: [String: Any] = [
            "timezone": "Europe/Berlin",
            "hourly": ["time": times, "temperature_2m": temperatures,
                       "precipitation_probability": probabilities, "wind_speed_10m": winds,
                       "wind_gusts_10m": gusts, "weather_code": codes],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let place = WeatherPlace(name: "Berlin", latitude: 52.52, longitude: 13.405, timezone: nil)
        let ref = try XCTUnwrap(OpenMeteo.day(from: data, date: date, place: place))
        XCTAssertEqual(ref.hours.map(\.hour), Array(6...19))
        XCTAssertTrue(ref.hours.allSatisfy { $0.rain == 0 })
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 10 })?.gust, 12)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 9 })?.gust, 30)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 11 })?.kind, .sun)
        XCTAssertEqual(ref.hours.first(where: { $0.hour == 12 })?.kind, .cloud)
    }

    func testForecastForAnotherDayIsIgnored() {
        let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                 timezone: nil)
        let ref = OpenMeteo.day(from: ForecastFixture.json(date: "2026-10-06", thunderAfternoon: true),
                                date: date, place: place)
        XCTAssertNil(ref)
    }

    func testTheGeocodeAnswerBecomesAPlace() throws {
        let json = #"{"results":[{"name":"München","country":"Germany","latitude":48.137,"longitude":11.575,"timezone":"Europe/Berlin"}]}"#
        let place = try XCTUnwrap(OpenMeteo.place(from: Data(json.utf8)))
        XCTAssertEqual(place.name, "München")
        XCTAssertEqual(place.latitude, 48.137)
        XCTAssertNil(OpenMeteo.place(from: Data("{}".utf8)))
    }

    func testTheRequestDefaultsToTomorrow() {
        let request = WeatherRequest.from([:])
        XCTAssertNil(request.place)
        XCTAssertEqual(request.day, .tomorrow)
        let named = WeatherRequest.from(["place": "Hamburg", "day": "dayAfter", "date": "2026-10-09"])
        XCTAssertEqual(named.place, "Hamburg")
        XCTAssertEqual(named.day, .dayAfter)
        XCTAssertEqual(named.date, "2026-10-09")
        let counted = WeatherRequest.from(["place": "Hamburg", "dayOffset": 4])
        XCTAssertEqual(counted.offset, 4)
        XCTAssertEqual(WeatherRequest.from(["dayOffset": "3"]).offset, 3)
        XCTAssertEqual(WeatherRequest.Day.at(index: 0), .today)
        XCTAssertEqual(WeatherRequest.Day.at(index: 2), .dayAfter)
        XCTAssertEqual(WeatherRequest.Day.at(index: 9), .tomorrow)
    }

    func testAnAbsurdDayOffsetIsBounded() {
        XCTAssertEqual(WeatherRequest.from(["dayOffset": 100_000]).offset, WeatherRequest.maxDayOffset)
        XCTAssertEqual(WeatherRequest.from(["dayOffset": -100_000]).offset, -WeatherRequest.maxDayOffset)
        XCTAssertEqual(WeatherRequest.from(["dayOffset": "-100000"]).offset, -WeatherRequest.maxDayOffset)
        XCTAssertEqual(WeatherRequest.from(["dayOffset": 4]).offset, 4)
    }

    func testTheStoredReferenceDecodesLeniently() throws {
        let json = #"{"place":"München","latitude":48.1,"longitude":11.5,"day":"2026-10-05","dayIndex":1,"hours":[{"hour":14,"temp":20.5,"rain":30,"gust":40,"kind":"rain"}]}"#
        let ref = try JSONDecoder().decode(WeatherRef.self, from: Data(json.utf8))
        XCTAssertEqual(ref.place, "München")
        XCTAssertEqual(ref.hours.count, 1)
        XCTAssertEqual(ref.hours.first?.kind, .rain)
        XCTAssertEqual(ref.hours.first?.precip, 0)
        XCTAssertTrue(ref.isOpenable)
        XCTAssertFalse(WeatherRef(place: "x", latitude: 0, longitude: 0, day: "",
                                  timezone: nil, hours: []).isOpenable)
    }

    @MainActor func testTheRequestedDateWinsOverTheDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12)) ?? Date()
        let service = WeatherService()
        let explicit = service.targetDate(WeatherRequest(place: "München", day: .dayAfter,
                                                         date: "2026-10-08"),
                                          now: now, calendar: calendar)
        XCTAssertEqual(explicit, "2026-10-08")
        let matching = service.targetDate(WeatherRequest(place: "München", day: .today,
                                                         date: "2026-10-08", offset: 4),
                                          now: now, calendar: calendar)
        XCTAssertEqual(matching, "2026-10-08")
        let conflicting = service.targetDate(WeatherRequest(place: "München", day: .today,
                                                            date: "2026-10-08", offset: 1),
                                             now: now, calendar: calendar)
        XCTAssertEqual(conflicting, "2026-10-08")
        let relative = service.targetDate(WeatherRequest(place: "München", day: .dayAfter, date: nil),
                                          now: now, calendar: calendar)
        XCTAssertEqual(relative, "2026-10-06")
        let counted = service.targetDate(WeatherRequest(place: "München", day: .today, date: nil, offset: 4),
                                         now: now, calendar: calendar)
        XCTAssertEqual(counted, "2026-10-08")
    }

    func testTheResolvedPlaceIsComparedLeniently() {
        XCTAssertTrue(WeatherService.samePlace("MÜNCHEN", "münchen"))
        XCTAssertTrue(WeatherService.samePlace("Buxtehude", "Buxtehude"))
        XCTAssertFalse(WeatherService.samePlace("Buxdehude", "Buxtehude"))
    }

    func testTheWeatherURLsCarryTheNeededFields() throws {
        let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                 timezone: nil)
        let forecast = try XCTUnwrap(OpenMeteo.forecastURL(place: place, date: date))
        let forecastText = forecast.absoluteString
        XCTAssertTrue(forecastText.contains("temperature_2m"))
        XCTAssertTrue(forecastText.contains("uv_index"))
        XCTAssertTrue(forecastText.contains("start_date=2026-10-05"))
        XCTAssertTrue(forecastText.contains("timezone=auto"))
        let geocode = try XCTUnwrap(OpenMeteo.geocodeURL(name: "München", language: .de))
        XCTAssertTrue(geocode.absoluteString.contains("name=M%C3%BCnchen")
                      || geocode.absoluteString.contains("name=München"))
    }
}
