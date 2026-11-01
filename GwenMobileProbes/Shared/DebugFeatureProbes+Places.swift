@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
final class ProbeRouteOpener: PlaceRouteOpening {
    struct Handoff {
        let place: NearbyPlace
        let url: URL?
        let openable: Bool
    }

    private(set) var handoffs: [Handoff] = []

    var last: Handoff? { handoffs.last }

    func open(_ place: NearbyPlace) -> Bool {
        let url = place.directionsURL
        let openable = url.map { UIApplication.shared.canOpenURL($0) } ?? false
        handoffs.append(Handoff(place: place, url: url, openable: openable))
        return openable
    }
}

extension DebugFeatureProbe {
    static func mapNearby(_ view: ChatView) async {
        await mapHandoff(view, nearby: true)
    }

    static func mapPlace(_ view: ChatView) async {
        await mapHandoff(view, nearby: false)
    }

    private static func mapHandoff(_ view: ChatView, nearby: Bool) async {
        let report = SweepReport(file: "map_mode.txt")
        let section = nearby ? "NÄHE" : "ZIEL"
        let mode = TravelMode.walking
        let kind: PlaceFlowRunner.Kind = nearby ? .nearby : .route
        let runner = PlaceFlowRunner(search: view.placeSearch, model: nil)
        let outcome = await runner.run(kind, terms: ["REWE"], wish: "", mode: mode)
        view.routeDesk.record(outcome.hits)
        guard let first = outcome.hits.first else {
            report.add(section, "treffer=0 übergeben=keine antwort=\(TextLine.oneLine(outcome.text, limit: 160))")
            flowMark("MAP \(section) keine treffer")
            return
        }
        view.openRoute(to: first.place)
        let handoff = (view.routeDesk.opener as? ProbeRouteOpener)?.last
        report.add(section, "treffer=\(outcome.hits.count) name=\(first.place.name) "
                   + "entfernt=\(first.place.distanceText ?? "unbekannt") modus=\(mode.rawValue) "
                   + "fahroption=\(mode.launchOption) "
                   + "übergeben=\(handoff?.openable ?? false) ziel=\(handoff?.place.name ?? "-") "
                   + "url=\(handoff?.url?.absoluteString ?? "keine")")
        flowMark("MAP \(section) fertig übergeben=\(handoff?.openable ?? false) "
                 + "ziel=\(handoff?.place.name ?? "-")")
    }

    static func placesDemo(_ view: ChatView) async {
        view.store.newConversation()
        view.input = "Wo ist der nächste REWE Supermarkt?"
        await view.send()
        view.input = "Rout mich mit dem Fahrrad zur Stadtbibliothek"
        await view.send()
        let messages = view.store.current?.messages ?? []
        flowLog.info("PLACESDEMO nachrichten=\(messages.count) orte=\(messages.map(\.allPlaces.count).reduce(0, +))")
    }

    static func routeFlow(_ view: ChatView) async {
        let report = SweepReport(file: "route_flow.txt")
        let asks = [("mit dem Rad zur Alexanderstraße 1 in 10178", "cycling"),
                    ("Rout mich mit dem Auto zur Torstraße 1", "driving"),
                    ("zu Fuß zur Stadtbibliothek", "walking"),
                    ("Wie komme ich mit Bus und Bahn zum Hauptbahnhof", "transit")]
        for (index, ask) in asks.enumerated() {
            view.store.newConversation()
            view.input = ask.0
            let started = ContinuousClock.now
            await view.send()
            let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
            let first = answer?.allPlaces.first
            report.add("FRAGE_\(index)", "ms=\(msOf(started.duration(to: .now))) modus_erwartet=\(ask.1) "
                       + "orte=\(answer?.allPlaces.count ?? -1) name=\(first?.name ?? "-") "
                       + "anzeige=\(first.map { "\($0.distanceText ?? "-") · \($0.mode.label)" } ?? "-") "
                       + "url=\(first?.directionsURL?.query ?? "keine")")
        }
        flowLog.info("ROUTEFLOW fertig")
    }

    static func placeProbe(_ view: ChatView) async {
        let report = SweepReport(file: "place_probe.txt")
        let fixer = LiveLocationFix()
        let search = LivePlaceSearch(fixer: fixer)
        report.add("ZUGRIFF", "status=\(fixer.accessState)")
        let started = ContinuousClock.now
        do {
            let hits = try await search.places(matching: ["REWE"], wish: "", mode: .walking)
            report.add("SUCHE", "treffer=\(hits.count) ms=\(msOf(started.duration(to: .now)))")
            for hit in hits {
                report.add("ORT", "\(hit.place.name) entfernt=\(hit.place.distanceText ?? "unbekannt") "
                           + "übergabe=\(hit.place.directionsURL == nil ? "keine" : "bereit")")
            }
        } catch {
            report.add("SUCHE", "fehler=\(TextLine.oneLine(error.localizedDescription, limit: 160)) ms=\(msOf(started.duration(to: .now)))")
        }
        let decision = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                         key: view.settings.apiKey,
                                                         model: view.settings.chatModel,
                                                         text: "Wo ist der nächste REWE?",
                                                         context: SendContext(), history: [],
                                                         thinking: view.settings.thinkingOffDirective(
                                                          for: view.settings.chatModel)))
        report.add("WERKZEUG", "route=\(decision.map { String(describing: $0.route) } ?? "keine") "
                   + "suchtext=\(decision?.searchQuery ?? "-")")

        do {
            let wide = try await search.places(matching: ["REWE Supermarkt"], wish: "", mode: .walking)
            report.add("SUCHE_BREIT", "treffer=\(wide.count) "
                       + "erste=\(wide.first.map { "\($0.place.name) \($0.place.distanceText ?? "?")" } ?? "-")")
        } catch { report.add("SUCHE_BREIT", "fehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))") }
        do {
            let filled = try await search.places(matching: ["REWE Supermarkt", "REWE"], wish: "", mode: .walking)
            report.add("SUCHE_MIT_ALTERNATIVE", "treffer=\(filled.count) "
                       + "erste=\(filled.first.map { "\($0.place.name) \($0.place.distanceText ?? "?")" } ?? "-")")
        } catch { report.add("SUCHE_MIT_ALTERNATIVE", "fehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))") }
        view.store.newConversation()
        view.input = "Wo ist der nächste REWE Supermarkt?"
        let flow = ContinuousClock.now
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("KETTENLAUF", "ms=\(msOf(flow.duration(to: .now))) orte=\(answer?.allPlaces.count ?? -1) "
                   + "zeichen=\(answer?.text.count ?? -1) antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 160))")
        report.add("KETTENLAUF_ÜBERGABE",
                   "url=\((answer?.allPlaces.first?.directionsURL?.absoluteString ?? "keine"))")
        flowLog.info("PLACEPROBE fertig")
    }

    static func routeProbe(_ view: ChatView) async {
        let report = SweepReport(file: "route_probe.txt")
        struct Golden {
            let text: String
            let attached: Bool
            let remembered: Bool
            let expected: SendRoute
            var history: [ChatMessage] = []
        }
        let cases = [
            Golden(text: "Wie viele Einwohner hat Deutschland?", attached: false, remembered: false, expected: .chat),
            Golden(text: "Wer hat den Eurovision Song Contest 2026 gewonnen?", attached: false,
                   remembered: false, expected: .chat),
            Golden(text: "Zeichne mir ein Ablaufdiagramm für den Anmeldevorgang", attached: false,
                   remembered: false, expected: .imageCreate),
            Golden(text: "Leg bitte morgen um 14 Uhr einen Zahnarzttermin für eine Stunde an",
                   attached: false, remembered: false, expected: .calendar),
            Golden(text: PictureProbe.lighten, attached: true, remembered: false,
                   expected: .imageEdit),
            Golden(text: "Übersetze den Text, den du auf dem Foto siehst, wörtlich ins Englische",
                   attached: true, remembered: false, expected: .chat),
            Golden(text: "Erzeuge ein Bild einer futuristischen Stadt bei Sonnenuntergang",
                   attached: false, remembered: false, expected: .imageCreate),
            Golden(text: "Programmiere mir Tetris als einzige HTML-Datei", attached: false,
                   remembered: false, expected: .code(language: .html)),
            Golden(text: "schreib mir ein Python-Skript, das alle Dateien in einem Ordner zählt",
                   attached: false, remembered: false, expected: .code(language: .python)),
            Golden(text: "Was ist auf dem Foto zu sehen?", attached: true, remembered: false, expected: .chat),
        ]
        var agreement = 0
        for (index, item) in cases.enumerated() {
            let context = SendContext(attachedImage: item.attached, rememberedImage: item.remembered)
            let started = ContinuousClock.now
            let decision = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                             key: view.settings.apiKey,
                                                             model: view.settings.chatModel,
                                                             text: item.text,
                                                             context: context, history: item.history,
                                                             thinking: view.settings.thinkingOffDirective(
                                                              for: view.settings.chatModel)))
            let ms = msOf(started.duration(to: .now))
            let chosen = decision?.route ?? .chat
            let same = chosen == item.expected
            if same { agreement += 1 }
            report.add("FALL_\(index)", "gleich=\(same) tool=\(String(describing: chosen)) "
                       + "erwartet=\(String(describing: item.expected)) "
                       + "suchtext=\(decision?.searchQuery ?? "-") termin=\(decision?.calendarAction.map { String(describing: $0) } ?? "-") ms=\(ms)")
        }
        report.add("TREFFER", "\(agreement)/\(cases.count)")
        flowLog.info("ROUTEPROBE fertig")
    }

}
#endif
