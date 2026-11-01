@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugChainFixtures {
    static func attachedRTF(_ text: String, view: ChatView) -> PendingFile? {
        let url = DebugFileProbe.richText(text)
        defer { try? FileManager.default.removeItem(at: url) }
        let documents = view.store.documents
        let extracted = DocumentExtractor.extract(url: url, kind: .rtf,
                                                 ocrLanguages: TextRecognizing.languages)
        guard let stored = documents.store(url: url) else { return nil }
        documents.writeText(extracted.text, for: stored.file)
        return PendingFile(name: "Notiz.rtf", kind: .rtf, file: stored.file, bytes: stored.bytes,
                           chars: extracted.chars, via: .richText, reading: false)
    }

    static func removeAppointments(refs: [CalendarRef], markers: [String], report: SweepReport) async {
        var wanted = refs.filter { !$0.eventID.isEmpty }
        for line in CalendarService.upcomingContext().split(separator: "\n") {
            let text = String(line).replacingOccurrences(of: "^- ", with: "", options: .regularExpression)
            let title = text.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard markers.contains(where: { title.localizedCaseInsensitiveContains($0) }) else { continue }
            if !wanted.contains(where: { $0.title == title }) { wanted.append(titleRef(title)) }
        }
        for ref in wanted {
            var weg = false
            do {
                weg = try CalendarService.remove(eventID: ref.eventID)
            } catch {
                report.add("AUFRÄUMEN", "titel=\(ref.title) FEHLER="
                           + TextLine.oneLine(error.localizedDescription, limit: 90))
            }
            if !weg {
                var plan = QwenAPI.CalendarPlan(action: .delete)
                plan.find = ref.title
                if let gone = try? await CalendarService.perform(plan) {
                    weg = true
                    report.add("AUFRÄUMEN", "titel=\(ref.title) weg=per_suche "
                               + TextLine.oneLine(gone.notice, limit: 90))
                }
            }
            report.add("AUFRÄUMEN", "titel=\(ref.title) id=\(ref.eventID.prefix(8)) weg=\(weg) "
                       + "live=\(CalendarService.isLive(ref.eventID))")
        }
    }

    private static func titleRef(_ title: String) -> CalendarRef {
        CalendarRef(eventID: "", title: title, start: Date())
    }

    static func cleanup(_ view: ChatView) async {
        let report = SweepReport(file: "gwen_cleanup.txt")
        let refs = view.store.conversations.flatMap(\.messages).compactMap(\.calendarRef)
            .filter { $0.title.localizedCaseInsensitiveContains("Gwen") }
        report.add("FUND", "termine=\(refs.count) titel=\(Set(refs.map(\.title)).sorted().joined(separator: ","))")
        await removeAppointments(refs: refs, markers: ["Gwen"], report: report)
        report.add("SUMME", "noch_live=\(refs.filter { CalendarService.isLive($0.eventID) }.count)")
        flowLog.info("AUFRÄUMEN fertig")
    }

    static func describe(_ answer: ChatMessage) -> String {
        "zeichen=\(answer.text.count) bilder=\(answer.outImages?.count ?? 0) "
            + "galerie=\(answer.gallery?.pictures.count ?? 0) orte=\(answer.allPlaces.count) "
            + "quellen=\(answer.sources?.count ?? 0) quellenkopf=\(answer.sourcesHeadingKey ?? "-") "
            + "termin=\(answer.calendarRef != nil) euromarken=\(answer.text.contains("€")) "
            + "anfang=\(TextLine.oneLine(String(answer.text.prefix(80)), limit: 90)) "
            + "ende=\(TextLine.oneLine(String(answer.text.suffix(80)), limit: 90))"
    }
}
#endif
