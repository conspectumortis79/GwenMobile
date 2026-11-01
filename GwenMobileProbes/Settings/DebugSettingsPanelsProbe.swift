@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit

@MainActor
enum DebugSettingsPanelsProbe {
    private struct ModelsPanel: View {
        var body: some View {
            NavigationStack {
                Form {
                    ModelsSettingsView(testResult: .constant(nil))
                }
            }
        }
    }

    static func run(_ view: ChatView) async {
        let started = ContinuousClock.now
        let report = SweepReport(file: "settings_panels.txt")
        report.add("DATEIEN", "settings_memory.jpg")
        report.add("DATEIEN", "settings_pricewatch.jpg")
        report.add("DATEIEN", "settings_music.jpg")
        report.add("DATEIEN", "settings_models.jpg")
        await memory(view, report: report)
        await priceWatch(view, report: report)
        await music(report: report)
        await models(report: report)
        report.add("DAUER", "ms=\(msOf(started.duration(to: .now)))")
        flowLog.info("EINSTELLUNGEN fertig")
    }

    private static func memory(_ view: ChatView, report: SweepReport) async {
        let store = view.store
        let marker = "Probe Merksatz \(UUID().uuidString.prefix(6))"
        guard let added = await store.memory.add(text: marker, category: .likes, source: .manual) else {
            report.add("MERKSATZ", "leer")
            return
        }
        let key = added.entry.shortKey
        let listed = await ProbeWait.poll(2) {
            await store.memory.all().contains { $0.text == marker }
        }
        await store.memory.setPinned(key: key, pinned: true)
        let pinned = await ProbeWait.poll(2) {
            let found = await store.memory.entry(key: key)
            return found?.pinned == true
        }
        let changed = marker + " neu"
        await store.memory.update(key: key, text: changed, category: .work, pinned: true, remind: false)
        let updated = await ProbeWait.poll(2) {
            let found = await store.memory.entry(key: key)
            return found?.text == changed
        }
        let export = await store.memory.exportData()
        let json = String(data: export, encoding: .utf8) ?? ""

        var screenshot = "kein_fenster"
        if let window = ProbeHosting.host(NavigationStack {
            MemoryView().environmentObject(store)
        }) {
            screenshot = await ProbeHosting.settledSnapshot(window, "settings_memory.jpg")
            ProbeHosting.close(window)
        }
        await store.memory.delete(key: key)
        let deleted = await ProbeWait.poll(2) {
            let found = await store.memory.entry(key: key)
            return found == nil
        }
        report.add("GEDÄCHTNIS", "angelegt=\(listed) neu=\(added.merged == false) angepinnt=\(pinned) "
                   + "geaendert=\(updated) export=\(export.count) json_enthaelt_text=\(json.contains(changed)) "
                   + "geloescht=\(deleted) screenshot=\(screenshot)")
    }

    private static func priceWatch(_ view: ChatView, report: SweepReport) async {
        let store = view.store
        let marker = "GwenProbeWatch\(UUID().uuidString.prefix(4))"
        guard let created = await store.watches.create(terms: [marker], goal: 123, intervalHours: 12,
                                                       currencyCode: "EUR", regionCode: "DE",
                                                       wording: "Probe") else {
            report.add("PREISWECKER", "anlegen_fehlgeschlagen")
            return
        }
        let id = created.watch.id
        let key = created.watch.shortKey
        let listed = await ProbeWait.poll(2) {
            await store.watches.all().contains { $0.id == id }
        }
        await store.watches.setPaused(id: id, paused: true)
        let paused = await ProbeWait.poll(2) {
            let found = await store.watches.all().first { $0.id == id }
            return found?.paused == true
        }
        await store.watches.setPaused(id: id, paused: false)
        let resumed = await ProbeWait.poll(2) {
            let found = await store.watches.all().first { $0.id == id }
            return found?.paused == false
        }
        let catalog = await store.watches.catalog()

        var screenshot = "kein_fenster"
        if let window = ProbeHosting.host(NavigationStack {
            PriceWatchView().environmentObject(store)
        }) {
            screenshot = await ProbeHosting.settledSnapshot(window, "settings_pricewatch.jpg")
            ProbeHosting.close(window)
        }
        await store.watches.delete(key: key, terms: [])
        let deleted = await ProbeWait.poll(2) {
            await store.watches.all().allSatisfy { $0.id != id }
        }
        report.add("PREISWECKER", "angelegt=\(created.created) gelistet=\(listed) pausiert=\(paused) "
                   + "fortgesetzt=\(resumed) katalog_enthaelt=\(catalog.contains(marker)) "
                   + "geloescht=\(deleted) screenshot=\(screenshot)")
    }

    private static func music(report: SweepReport) async {
        let settings = AppSettings.shared
        let original = settings.music.service
        let alternative: MusicService = original == .spotify ? .appleMusic : .spotify
        settings.music.service = alternative
        let switched = await ProbeWait.until(2) { settings.music.service == alternative }
        settings.music.service = original
        let restored = await ProbeWait.until(2) { settings.music.service == original }
        let services = MusicService.allCases.map(\.rawValue).joined(separator: ",")
        let cleaned = SpotifyConfig.cleaned("  ProbeClientID  ")

        var screenshot = "kein_fenster"
        if let window = ProbeHosting.host(NavigationStack {
            Form {
                MusicSettingsSection(settings: settings)
            }
        }) {
            screenshot = await ProbeHosting.settledSnapshot(window, "settings_music.jpg")
            ProbeHosting.close(window)
        }
        report.add("MUSIK", "dienste=\(services) gewechselt=\(switched) zurueck=\(restored) "
                   + "spotify_da=\(SpotifyLink.isAvailable) angemeldet=\(SpotifyLink.shared.signedIn) "
                   + "clientID_bereinigt=\(cleaned) screenshot=\(screenshot)")
    }

    private static func models(report: SweepReport) async {
        let settings = AppSettings.shared
        var screenshot = "kein_fenster"
        if let window = ProbeHosting.host(ModelsPanel()) {
            screenshot = await ProbeHosting.settledSnapshot(window, "settings_models.jpg")
            ProbeHosting.close(window)
        }
        let profile = settings.profile
        let caps = settings.capabilities
        report.add("MODELLE", "chat=\(settings.chatModel) text=\(profile.textCandidates.count) "
                   + "vision=\(settings.visionModel) visionliste=\(profile.visionCandidates.count) "
                   + "bild=\(settings.imageModel) bildliste=\(profile.imageCandidates.count) "
                   + "anbieter=\(settings.provider.rawValue) geladen=\(settings.availableModels.count) "
                   + "chat_rechte=\(caps.chat.rawValue) vision_rechte=\(caps.vision.rawValue) "
                   + "bild_rechte=\(caps.image.rawValue) screenshot=\(screenshot)")
    }

}
#endif
