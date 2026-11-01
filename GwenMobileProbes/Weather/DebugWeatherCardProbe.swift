@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit

@MainActor
enum DebugWeatherCardProbe {
    @MainActor final class HourBox: ObservableObject {
        @Published var value: Int?
    }

    private struct ProbeCard: View {
        let ref: WeatherRef
        @ObservedObject var hour: HourBox
        let selected: (Int) -> Void
        let picked: (String) -> Void

        var body: some View {
            WeatherCard(ref: ref,
                        onDay: { picked($0) },
                        onSpeak: nil,
                        showsActions: true,
                        probeHour: Binding(get: { hour.value }, set: { hour.value = $0 }),
                        probeHourValue: hour.value,
                        probeSelectedHour: selected)
        }
    }

    static func run(_ view: ChatView) async {
        let started = ContinuousClock.now
        let report = SweepReport(file: "weather_card.txt")
        let language = L.lang
        L.apply(.de)
        defer { L.apply(language) }

        let today = WeatherDayTabs.stamp(Date())
        let tomorrow = WeatherDayTabs.stamp(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                 timezone: "Europe/Berlin")
        guard let ref = OpenMeteo.day(from: DebugShotProbe.shotForecastJSON(date: tomorrow),
                                      date: tomorrow, place: place) else {
            report.add("AUFBAU", "fixture nicht lesbar")
            return
        }
        let hours = ref.hours.map(\.hour)
        report.add("AUFBAU", "sprache=\(language.rawValue) heute=\(today) morgen=\(tomorrow) "
                   + "stunden=\(hours.count) von=\(hours.first ?? -1) bis=\(hours.last ?? -1) "
                   + "reiter=\(WeatherDayTabs.dates(selected: ref.day).joined(separator: ","))")

        await cardInteractions(ref, report: report)
        await chatSwitch(ref, today: today, view: view, report: report)

        report.add("DAUER", "ms=\(msOf(started.duration(to: .now)))")
        flowLog.info("WETTERKARTE fertig")
    }

    private static func cardInteractions(_ ref: WeatherRef, report: SweepReport) async {
        let hour = HourBox()
        var observed: [Int] = []
        var pickedDays: [String] = []
        let card = ProbeCard(ref: ref, hour: hour, selected: { observed.append($0) },
                             picked: { pickedDays.append($0) })
        guard let window = ProbeHosting.host(card) else {
            report.add("KARTE", "kein fenster")
            return
        }
        defer { ProbeHosting.close(window) }

        let defaultHour = ref.hours.first(where: { $0.hour == 14 })?.hour ?? ref.hours.first?.hour ?? 0
        let wanted = ref.hours.first { $0.hour == 9 }?.hour ?? ref.hours.dropFirst(2).first?.hour ?? 0
        let shown = await ProbeWait.until(3) { observed.last == defaultHour }
        report.add("KARTE", "standard=\(defaultHour) gelesen=\(shown) reihe=\(observed)")

        let t0 = ContinuousClock.now
        hour.value = wanted
        let switched = await ProbeWait.until(3) { observed.last == wanted }
        report.add("STUNDENWAHL", "ziel=\(wanted) erreicht=\(switched) reihe=\(observed) "
                   + "ms=\(msOf(t0.duration(to: .now)))")

        let back = ContinuousClock.now
        hour.value = defaultHour
        let restored = await ProbeWait.until(3) { observed.last == defaultHour }
        report.add("STUNDENWAHL_ZURUECK", "erreicht=\(restored) "
                   + "ms=\(msOf(back.duration(to: .now)))")

        touchSurface(ref, window: window, hour: hour, report: report)
        hour.value = defaultHour
        _ = await ProbeWait.until(3) { observed.last == defaultHour }

        report.add("TAGESREITER", "gewaehlt=\(pickedDays.count) grund=kein_synthetischer_tipp "
                   + "aktion=switchWeatherDay")
        report.add("SCREEN", ProbeHosting.snapshot(window, "weather_card.jpg"))
    }

    private static func touchSurface(_ ref: WeatherRef, window: UIWindow, hour: HourBox, report: SweepReport) {
        guard let surface = ViewSearching.all(in: window).compactMap({ $0 as? WeatherScrubView }).first else {
            report.add("TOUCHFLAECHE", "nicht gefunden")
            return
        }
        let frame = surface.convert(surface.bounds, to: window)
        report.add("TOUCHFLAECHE", "rahmen=\(Int(frame.minX)),\(Int(frame.minY)),"
                   + "\(Int(frame.width))x\(Int(frame.height))")

        let samples: [(String, CGPoint)] = [
            ("links", CGPoint(x: frame.minX + 2, y: frame.midY)),
            ("rechts", CGPoint(x: frame.maxX - 2, y: frame.midY)),
            ("kurve", CGPoint(x: frame.midX, y: frame.minY + 4)),
            ("leiste", CGPoint(x: frame.midX, y: frame.maxY - 12)),
            ("labels", CGPoint(x: frame.midX, y: frame.maxY - 2)),
        ]
        var hits = 0
        for (name, point) in samples {
            let hit = window.hitTest(point, with: nil)
            let inside = hit === surface || (hit?.isDescendant(of: surface) ?? false)
            hits += inside ? 1 : 0
            report.add("TREFFER", "\(name)=\(inside ? "ok" : "vorbei:\(hit.map { String(describing: type(of: $0)) } ?? "nil")")")
        }
        let below = window.hitTest(CGPoint(x: frame.midX, y: frame.maxY + 6), with: nil)
        let belowInside = below === surface || (below?.isDescendant(of: surface) ?? false)
        report.add("HITTEST", "treffer=\(hits)/\(samples.count) unterhalb=\(belowInside ? "drin" : "draussen")")

        let count = CGFloat(ref.hours.count)
        let spacing: CGFloat = 2
        let column = (frame.width - spacing * (count - 1)) / count
        var wrong: [String] = []
        for (index, item) in ref.hours.enumerated() {
            let x = CGFloat(index) * (column + spacing) + column / 2
            let mapped = surface.probeHour(atX: x)
            if mapped != item.hour { wrong.append("\(item.hour)->\(mapped.map { String($0) } ?? "-")") }
        }
        report.add("SPALTEN", "geprueft=\(ref.hours.count) "
                   + "falsch=\(wrong.isEmpty ? "keine" : wrong.joined(separator: ","))")

        let wanted = ref.hours.dropFirst(4).first?.hour ?? ref.hours.first?.hour ?? 0
        let index = ref.hours.firstIndex { $0.hour == wanted } ?? 0
        let x = CGFloat(index) * (column + spacing) + column / 2
        surface.probeSelect(atX: x)
        report.add("AUSWAHLPFAD", "ziel=\(wanted) gesetzt=\(hour.value.map { String($0) } ?? "-") "
                   + "erreicht=\(hour.value == wanted)")

        report.add("RICHTUNG", "waagerecht=\(surface.shouldScrub(velocity: CGPoint(x: 80, y: 8))) "
                   + "senkrecht=\(surface.shouldScrub(velocity: CGPoint(x: 6, y: 60)))")
    }

    private static func chatSwitch(_ ref: WeatherRef, today: String, view: ChatView,
                                   report: SweepReport) async {
        view.store.newConversation()
        guard let conv = view.store.current?.id else {
            report.add("CHAT", "keine unterhaltung")
            return
        }
        let question = ChatMessage(role: .user, text: "Wie wird das Wetter morgen in München?")
        view.store.appendMessage(question, to: conv)
        let advice = WeatherAdviceRules.advice(for: ref)
        var answer = ChatMessage(role: .assistant, text: WeatherAnswers.text(ref: ref, advice: advice),
                                 model: "probe", elapsed: 1)
        answer.weatherRef = ref
        view.store.appendMessage(answer, to: conv)
        guard await ProbeHosting.waitForMainWindow() != nil else {
            report.add("CHAT", "kein hauptfenster")
            return
        }
        report.add("CHAT", "start_tag=\(ref.day) heute=\(today) nachrichten=\(view.store.current?.messages.count ?? -1)")

        let alertsBefore = view.probeAlerts.count
        let t0 = ContinuousClock.now
        await view.switchWeatherDay(message: answer.id, date: today)
        let arrived = await ProbeWait.until(10) {
            view.store.current?.messages.first { $0.id == answer.id }?.weatherRef?.day == today
                || view.probeAlerts.count > alertsBefore
        }
        let changed = view.store.current?.messages.first { $0.id == answer.id }
        report.add("CHAT_TAGSWECHSEL", "erreicht=\(arrived) tag=\(changed?.weatherRef?.day ?? "-") "
                   + "erwartet=\(today) stunden=\(changed?.weatherRef?.hours.count ?? -1) "
                   + "fehler=\(view.probeAlerts.count - alertsBefore) ms=\(msOf(t0.duration(to: .now)))")
        _ = view.store.removeConversation(conv)
    }
}
#endif
