#if DEBUG
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugVideoProbe {
    private static let sentence = "Erstelle ein 5 Sekunden langes Video von einem Sonnenuntergang über dem Meer."
    private static let prompt = "A sunset over the sea, gentle waves, warm evening light"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "video_probe.txt")
        let settings = view.settings
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        let backend = settings.descriptor.videoGenerationBackend
        report.add("KONFIG", "anbieter=\(settings.provider.rawValue) "
                   + "konfiguriert=\(settings.isConfigured) schluessel=\(!settings.apiKey.isEmpty) "
                   + "backend=\(backend.map { String(describing: type(of: $0)) } ?? "keins")")
        report.add("MODELLE", "chat=\(settings.chatModel) vision=\(settings.visionModel) "
                   + "bild=\(settings.imageModel) video_analyse=\(settings.videoModel) "
                   + "video_erzeugung=\(settings.videoGenerationModel) "
                   + "bild_erzeugung=\(settings.hasImageModel) video_erzeugung_bereit="
                   + "\(settings.hasVideoGenerationModel)")
        guard settings.isConfigured else {
            report.add("ABBRUCH", "anbieter nicht konfiguriert")
            return
        }
        let routed = await chatPath(view, report: report)
        if !routed { await backendPath(view, report: report) }
        let removed = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        report.add("AUFRAEUMEN", "entfernt=\(removed) anbieter=\(settings.provider.rawValue)")
    }

    private static func chatPath(_ view: ChatView, report: SweepReport) async -> Bool {
        report.add("FRAGE", sentence)
        let started = ContinuousClock.now
        let answers = await DebugFeatureProbe.freshAsk(view, sentence, log: "VIDEO frage", resetPlan: true)
        let ms = msOf(started.duration(to: .now))
        let plan = view.probeLastPlan
        let routed = plan?.actions.contains { $0.stepKind == .video } ?? false
        report.add("PLAN", "\(plan?.traceLine ?? "keine") video=\(routed) ms=\(ms)")
        let text = answers.map(\.text).joined(separator: " ")
        report.add("ANTWORT", "blasen=\(answers.count) zeichen=\(text.count) "
                   + "text=\(TextLine.oneLine(text, limit: 400))")
        let files = answers.flatMap(\.files).filter { $0.kind == .video }
        let stored = files.first
        let data = stored.flatMap { view.store.documents.data(named: $0.file) }
        report.add("FLOW", "dateien=\(files.count) name=\(stored?.name ?? "-") "
                   + "datei=\(stored?.file ?? "-") bytes=\(stored?.bytes ?? -1) "
                   + "geladen=\(data?.count ?? -1) video=\(data.map(VideoBytes.isVideo) ?? false)")
        if let stored { view.store.documents.discardStored([stored.file]) }
        return routed
    }

    private static func backendPath(_ view: ChatView, report: SweepReport) async {
        guard let backend = view.settings.descriptor.videoGenerationBackend else {
            report.add("BACKEND", "keins beim anbieter \(view.settings.provider.rawValue)")
            return
        }
        let model = view.settings.videoGenerationModel
        let documents = view.store.documents
        let started = ContinuousClock.now
        do {
            let generated = try await backend.generate(baseURL: view.settings.baseURL,
                                                       key: view.settings.apiKey, model: model,
                                                       request: VideoRequest(prompt: prompt), sourceVideo: nil)
            let ms = msOf(started.duration(to: .now))
            let stored = await Offload.orNilFlat(priority: .utility, {
                documents.store(data: generated.data, fileExtension: generated.fileExtension)
            })
            let loaded = stored.flatMap { documents.data(named: $0.file) }
            report.add("BACKEND", "modell=\(model) bytes=\(generated.data.count) "
                       + "endung=\(generated.fileExtension) video=\(VideoBytes.isVideo(generated.data)) "
                       + "ms=\(ms) ablage=\(stored?.file ?? "-") gleich=\(loaded == generated.data)")
            if let stored { documents.discardStored([stored.file]) }
        } catch {
            report.addFailure("BACKEND", error)
        }
    }
}
#endif
#endif
