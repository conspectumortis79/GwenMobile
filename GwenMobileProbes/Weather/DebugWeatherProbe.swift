@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugWeatherProbe {
    private struct RouteCase {
        let sentence: String
        let place: String?
        var dateOffset: Int? = nil
        var clock = false
    }

    private static let routeCases = [
        RouteCase(sentence: "Wie wird das Wetter morgen in München?", place: "münchen", dateOffset: 1),
        RouteCase(sentence: "Regnet es übermorgen in Hamburg?", place: "hamburg", dateOffset: 2),
        RouteCase(sentence: "Brauche ich heute in Berlin Sonnenschutz?", place: "berlin", dateOffset: 0),
        RouteCase(sentence: "Brauche ich hier morgen einen Schirm?", place: nil, dateOffset: 1),
        RouteCase(sentence: "Wie wird das Wetter in 4 Tagen in München?", place: "münchen", dateOffset: 4),
        RouteCase(sentence: "Wie wird das Wetter überübermorgen in Hamburg?", place: "hamburg", dateOffset: 3),
        RouteCase(sentence: "What will the weather be like in London the day after the day after tomorrow?",
                  place: "london", dateOffset: 3),
        RouteCase(sentence: "Quel temps fera-t-il à Paris après-après-demain ?", place: "paris", dateOffset: 3),
        RouteCase(sentence: "¿Qué tiempo hará en Madrid pasado pasado mañana?", place: "madrid", dateOffset: 3),
        RouteCase(sentence: "Wie spät ist es?", place: nil, clock: true)
    ]

    static func routing(_ view: ChatView) async {
        let planReport = SweepReport(file: "weather_route_plan.txt")
        let twoDays = SendPlan.forming([
            ToolDecision(route: .weather(WeatherRequest(place: "München", day: .today,
                                                       date: nil, offset: 0))),
            ToolDecision(route: .weather(WeatherRequest(place: "München", day: .dayAfter,
                                                       date: nil, offset: 2))),
        ])
        planReport.add("ZWEI_TAGE", "\(twoDays.traceLine) schritte=\(twoDays.actions.count) "
                       + "schluessel=\(Set(twoDays.actions.map(\.stepKey)).count)")
        await RouteSweep.routeAll(routeCases, file: "weather_route.txt", view: view,
                                  log: "WETTERROUTING fertig",
                                  fits: { fitting($0, plan: $1) },
                                  label: expectedLabel, sentence: { $0.sentence },
                                  detail: describe)
    }

    static func decode() async {
        let report = SweepReport(file: "weather_decode.txt")
        let date = "2026-10-05"
        let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                 timezone: "Europe/Berlin")
        guard let ref = OpenMeteo.day(from: forecastJSON(date: date), date: date, place: place) else {
            report.add("DECODE", "fehlgeschlagen")
            return
        }
        let advice = WeatherAdviceRules.advice(for: ref)
        let text = WeatherAnswers.text(ref: ref, advice: advice)
        report.add("STUNDEN", "anzahl=\(ref.hours.count) von=\(ref.hours.first?.hour ?? -1) "
                   + "bis=\(ref.hours.last?.hour ?? -1) zone=\(ref.timezone ?? "-")")
        report.add("ARTEN", ref.hours.map(\.kind.rawValue).joined(separator: ","))
        report.add("HINWEISE", advice.map(\.title).joined(separator: " | "))
        report.add("UV_FENSTER", WeatherAdviceRules.uvWindow(ref) ?? "-")
        report.add("TEXT", TextLine.oneLine(text, limit: 220))
        report.add("WERT", WeatherAnswers.hourLine(ref, hour: 14))
        flowLog.info("WETTERDECODE fertig")
    }

    static func flow() async {
        let report = SweepReport(file: "weather_flow.txt")
        let service = WeatherService()
        for place in ["München", "Hamburg", "Buxdehude"] {
            let started = ContinuousClock.now
            do {
                let ref = try await service.day(for: WeatherRequest(place: place, day: .tomorrow, date: nil))
                let advice = WeatherAdviceRules.advice(for: ref)
                report.add("\(place) → \(ref.place)", "stunden=\(ref.hours.count) zone=\(ref.timezone ?? "-") "
                           + "von=\(ref.hours.first?.hour ?? -1) bis=\(ref.hours.last?.hour ?? -1) "
                           + "hinweise=\(advice.map(\.title).joined(separator: " | ")) "
                           + "ms=\(msOf(started.duration(to: .now)))")
                report.add("\(place)_TEXT",
                           TextLine.oneLine(WeatherAnswers.text(ref: ref, advice: advice), limit: 240))
            } catch {
                report.addFailure(place, error)
            }
        }
        if let plusFour = Calendar.current.date(byAdding: .day, value: 4, to: Date()) {
            let date = WeatherDayTabs.stamp(plusFour)
            let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                     timezone: "Europe/Berlin")
            do {
                let ref = try await service.day(place: place, date: date)
                let advice = WeatherAdviceRules.advice(for: ref)
                report.add("München +4 Tage (\(ref.day))",
                           "stunden=\(ref.hours.count) hinweise=\(advice.map(\.title).joined(separator: " | "))")
                report.add("München_+4_TEXT",
                           TextLine.oneLine(WeatherAnswers.text(ref: ref, advice: advice), limit: 240))
            } catch {
                report.addFailure("München +4", error)
            }
        }
        flowLog.info("WETTERFLOW fertig")
    }

    static func chat(_ view: ChatView) async {
        let report = SweepReport(file: "weather_chat.txt")
        let settings = view.settings
        guard settings.isConfigured else {
            report.add("ABBRUCH", "kein schluessel")
            flowLog.info("WETTERCHAT abbruch")
            return
        }
        let before = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        report.add("KONFIG", "modell=\(settings.answeringModel(hasPictures: false))")
        let cases = [ChatCase(label: "MÜNCHEN", question: "Wie wird das Wetter morgen in München?",
                              place: "münchen"),
                     ChatCase(label: "BUXTEHUDE",
                              question: "Wie wird das Wetter morgen in Buxdehude?",
                              place: "buxtehude"),
                     ChatCase(label: "IN_4_TAGEN",
                              question: "Wie wird das Wetter in 4 Tagen in München?",
                              place: "münchen", dateOffset: 4)]
        for item in cases {
            let message = await view.ask(item.question, fresh: true)
            if let ref = message?.weatherRef {
                let advice = WeatherAdviceRules.advice(for: ref)
                let placeFits = TextFolding.fold(ref.place).lowercased()
                    .contains(TextFolding.fold(item.place).lowercased())
                let expected = item.dateOffset.flatMap { expectedDate($0) }
                let dayFits = expected == nil || ref.day == expected
                report.add(item.label, "passt=\(placeFits && dayFits) ort=\(ref.place) tag=\(ref.day) "
                           + "erwartet=\(expected ?? "-") stunden=\(ref.hours.count) "
                           + "hinweise=\(advice.map(\.title).joined(separator: " | "))")
                report.add(item.label + "_TEXT", TextLine.oneLine(message?.text ?? "", limit: 240))
            } else {
                report.add(item.label,
                           "kein weatherRef: \(TextLine.oneLine(message?.text ?? "-", limit: 160))")
            }
        }
        for conversation in view.store.conversations where !before.contains(conversation.id) {
            view.store.cleaner.deleteConversation(conversation.id)
        }
        if let previous, view.store.conversations.contains(where: { $0.id == previous }) {
            view.store.currentID = previous
        }
        flowLog.info("WETTERCHAT fertig")
    }

    private struct ChatCase {
        let label: String
        let question: String
        let place: String
        var dateOffset: Int? = nil
    }

    private static func expectedLabel(_ item: RouteCase) -> String {
        if item.clock { return "clock" }
        return item.dateOffset.map { "weather+\($0)d" } ?? "weather"
    }

    private static func expectedDate(_ offset: Int) -> String? {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()).map(WeatherDayTabs.stamp)
    }

    private static func fitting(_ item: RouteCase, plan: SendPlan) -> Bool {
        if item.clock { return plan.primary.stepKind == .clock }
        guard let offset = item.dateOffset, plan.primary.stepKind == .weather,
              case .weather(let request) = plan.primary.route else { return false }
        if let place = item.place {
            guard (request.place ?? "").lowercased().contains(place) else { return false }
        } else {
            guard (request.place ?? "").isEmpty else { return false }
        }
        return WeatherService().targetDate(request, now: Date(), calendar: .current) == expectedDate(offset)
    }

    private static func describe(_ plan: SendPlan) -> String {
        guard case .weather(let request) = plan.primary.route else { return plan.traceLine }
        return "ort=\(request.place ?? "-") tag=\(request.date ?? "-") "
            + "versatz=\(request.offset.map(String.init) ?? "-") wahl=\(request.day.rawValue)"
    }

    static func forecastJSON(date: String) -> Data {
        ForecastFixture.json(date: date, thunderAfternoon: true)
    }
}
#endif
