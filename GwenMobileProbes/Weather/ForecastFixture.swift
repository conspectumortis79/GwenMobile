#if DEBUG
import GwenMobileKit
import Foundation

enum ForecastFixture {
    static func json(date: String, thunderAfternoon: Bool = false) -> Data {
        var times: [String] = []
        var temps: [Double] = []
        var probs: [Int] = []
        var precips: [Double] = []
        var winds: [Double] = []
        var gusts: [Double] = []
        var uvs: [Double] = []
        var codes: [Int] = []
        for hour in 0..<24 {
            times.append(date + "T" + String(format: "%02d:00", hour))
            temps.append(Double(hour))
            probs.append(min(100, hour * 4))
            precips.append(hour >= 12 ? 0.5 : 0)
            winds.append(10 + Double(hour) / 2)
            gusts.append(20 + Double(hour))
            uvs.append(Double(min(8, hour / 3)))
            codes.append(hour == 15 && thunderAfternoon ? 95 : hour == 9 ? 61 : 0)
        }
        let object: [String: Any] = [
            "timezone": "Europe/Berlin",
            "hourly": ["time": times, "temperature_2m": temps, "precipitation_probability": probs,
                       "precipitation": precips, "wind_speed_10m": winds, "wind_gusts_10m": gusts,
                       "uv_index": uvs, "weather_code": codes]
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
#endif
