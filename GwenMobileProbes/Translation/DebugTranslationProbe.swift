@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugTranslationProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "translation_probe.txt")
        report.add("ANHANG", "bild_im_anhang=" + gate(SendContext(attachedImage: true))
                   + " datei_im_anhang=" + gate(SendContext(attachedFile: true))
                   + " erinnertes_bild=" + gate(SendContext(rememberedImage: true))
                   + " ohne_anhang=" + gate(SendContext()))
        report.add("GERÄT", "system=\(ProcessInfo.processInfo.operatingSystemVersion)")
        let codes = await OnDeviceTranslation.supportedCodes()
        report.add("SPRACHEN", "anzahl=\(codes.count) " + Set(codes).sorted().joined(separator: ","))
        for target in ["en", "fr", "tr", "zh-Hans", "ja"] {
            let job = TranslationJob(text: "Wo ist der nächste Bahnhof?", targetCode: target)
            let status = await OnDeviceTranslation.status(for: job)
            report.add("PAAR", "de→\(target) status=\(status)")
            guard status == .ready else { continue }
            let started = ContinuousClock.now
            do {
                let text = try await OnDeviceTranslation.translate(job)
                report.add("ÜBERSETZ", "de→\(target) ms=\(msOf(started.duration(to: .now))) text=\(text)")
            } catch {
                report.add("ÜBERSETZ", "de→\(target) FEHLER \(error.localizedDescription)")
            }
        }
        let long = String(repeating: "Der Cache bleibt lokal auf dem Gerät. ", count: 60)
        let chunks = TranslationChunks.split(long)
        report.add("STÜCKE", "zeichen=\(long.count) stücke=\(chunks.count) "
                   + "groesse=\(chunks.map { "\($0.count)" }.joined(separator: ",")) "
                   + "zusammen=\(chunks.joined() == long)")
        let sent = try? await OnDeviceTranslation.translate(TranslationJob(text: long, targetCode: "en"))
        report.add("LANG", "zeichen=\(sent?.count ?? -1) anfang=\(TextLine.oneLine(sent ?? "", limit: 70))")
        let vorher = view.settings.voice.speakAnswers
        view.settings.voice.speakAnswers = false
        view.store.newConversation()
        view.input = "Erkläre in einem Satz, was ein Regal ist."
        await view.send()
        let beantwortet = view.store.current?.messages.last(where: { $0.role == .assistant })?.text ?? ""
        view.input = "Übersetze das ins Französische"
        await view.send()
        let übersetzt = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("CHAT", "antwort=\(TextLine.oneLine(beantwortet, limit: 60)) "
                   + "übersetzt=\(TextLine.oneLine(übersetzt?.text ?? "", limit: 70)) "
                   + "signatur=\(übersetzt?.model ?? "-")")
        let probeJob = TranslationJob(text: beantwortet, targetCode: "cs")
        let fallbackStatus = await OnDeviceTranslation.status(for: probeJob)
        view.input = "Und jetzt auf Tschechisch"
        await view.send()
        let fallback = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("FALLBACK", "ziel=cs gerät=\(fallbackStatus) "
                   + "text=\(TextLine.oneLine(fallback?.text ?? "", limit: 70)) "
                   + "signatur=\(fallback?.model ?? "-")")
        view.settings.voice.speakAnswers = vorher
        flowLog.info("ÜBERSETZUNG probe fertig")
    }

    private static func gate(_ context: SendContext) -> String {
        let werkzeuge = ToolRouter.tools(attachable: context.attachedImage || context.rememberedImage,
                                         translatesOnDevice: !context.textNeedsTheModel)
            .compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        return "werkzeug=\(werkzeuge.contains(ToolRouter.translateTool)) routing=modell "
    }

}
#endif
