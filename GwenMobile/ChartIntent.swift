import Foundation

enum ChartIntent {
    static let visualSignal = PhraseMatch(phrases: ["diagramm", "diagrammen", "grafik", "graphik", "infografik",
                                                    "chart", "graphische", "visualis", "visualisier", "veranschaulich",
                                                    "balken", "balkendiagramm", "säulen", "saeulen", "kreisdiagramm",
                                                    "liniendiagramm", "kurve", "heatmap", "punktwolke", "plot",
                                                    "diagram", "plots"])
    static let dataSignal = PhraseMatch(phrases: ["statistik", "statistiken", "zahlen", "daten", "werte", "werten",
                                                  "prozent", "anteil", "anteile", "vergleich", "entwicklung",
                                                  "trend", "ranking", "verteilung", "anzahl", "umsatz", "einwohner",
                                                  "bevölkerung", "bevolkerung", "kosten", "einkommen", "rate",
                                                  "raten", "sales", "ertrag", "marge", "inzidenz", "sterblichkeit",
                                                  "geburten", "wahlen", "stimmen", "ergebnis", "ergebnisse",
                                                  "statistic", "numbers", "data", "values", "percentage", "revenue",
                                                  "population", "growth", "amount", "share of", "gdp", "temperature"])
    static let webSignal = PhraseMatch(phrases: ["internet", "im web", "aus dem web", "recherch", "googl", "suche",
                                                 "such nach", "such mir", "lookup", "aktuell", "derzeit", "momentan",
                                                 "online", "website", "statista", "wikipedia", "destatis",
                                                 "world bank", "eurostat", "current", "latest", "this year",
                                                 "newest", "look up", "find out"])
    static let rejection = PhraseMatch(phrases: ["kein diagramm", "keine grafik", "keine grafiken", "ohne diagramm",
                                                 "ohne grafik", "nicht als diagramm", "keine visualisierung",
                                                 "kein bild", "no chart", "not a chart", "no graph",
                                                 "without a chart", "don't chart", "dont chart", "don't plot",
                                                 "dont plot", "nur text", "nur als text", "nur eine antwort"])

    static let creationVerb = PhraseMatch(phrases: ["mach", "erstell", "erzeug", "baue", "visualisier",
                                                    "veranschaulich", "make", "create", "generate", "build",
                                                    "plot", "draw", "chart it"])

    static let existingVisual = PhraseMatch(phrases: ["im diagramm", "in dem diagramm", "dem diagramm", "das diagramm",
                                                      "dein diagramm", "diesem diagramm", "diagramm gezeigt",
                                                      "diagramm eingezeichnet", "diagramm eingetragen", "diagramm genutzt",
                                                      "diagramm dargestellt", "im graf", "in der grafik", "der grafik",
                                                      "im chart", "in dem chart", "the chart", "this chart",
                                                      "your chart", "in the chart", "the graph", "this graph",
                                                      "your graph", "the visualisation", "the visualization"])

    static func looksLikeChartRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        guard visualSignal.matches(t), !rejection.matches(t) else { return false }
        guard !refersToExistingVisual(t) else { return false }
        return dataSignal.matches(t) || webSignal.matches(t)
    }

    static func refersToExistingVisual(_ lowered: String) -> Bool {
        guard existingVisual.matches(lowered) else { return false }
        return !(creationVerb.matches(lowered) && visualSignal.matches(lowered))
    }

    static func wantsWebData(_ text: String) -> Bool {
        webSignal.matches(text.lowercased())
    }
}
