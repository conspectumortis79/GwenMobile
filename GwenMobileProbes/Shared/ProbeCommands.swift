@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit
import AVFoundation

let flowTestBigImage = "img_0B85747A-BAA.jpg"
let flowTestEditImage = "img_7924D952-6BF.jpg"
let flowTestRounds = ProbeRounds.maximum

extension ChatView {
    func lastImageCandidate() -> Attachment? {
        ConversationMemory.turn(from: store.current?.messages ?? []) { store.media.data(for: $0) }
            .pictureFiles.last.map { Attachment(file: $0) }
    }

    func flowTestPicture(named file: String = flowTestBigImage) async -> UIImage? {
        guard let stored = store.media.data(named: file) else {
            flowLog.error("TEST no big image file")
            return nil
        }
        guard let picture = await Task.detached(priority: .userInitiated, operation: {
            MediaStore.thumbnail(stored, maxPixel: ImagePolicy.uploadMaxPixel)
        }).value else {
            flowLog.error("TEST no thumbnail")
            return nil
        }
        return picture
    }

    func runFlowTest(_ name: String) async {
        let snapshot = ProbeSettingsGuard.begin(settings, probe: name)
        defer { ProbeSettingsGuard.restore(snapshot, to: settings) }
        if await DebugFeatureProbe.run(name, view: self) { return }
        if await DebugFileProbe.run(name, view: self) { return }
        guard let test = Self.flowTest(named: name) else {
            await attachAndEdit(name)
            return
        }
        await withScreenAwake { await test(self) }
    }

    static func shotTest(named name: String) -> (@MainActor (ChatView) async -> Void)? {
        switch name {
        case "shotchat": return { view in await DebugShotProbe.chat(view) }
        case "shotplusmenu": return { view in await DebugShotProbe.plusMenu(view) }
        case "shotsettings": return { view in await DebugShotProbe.settings(view) }
        case "shothistories": return { view in await DebugShotProbe.histories(view) }
        case "shotsettingsvoice": return { view in await DebugShotProbe.settingsVoice(view) }
        case "shotsettingsmodels": return { view in await DebugShotProbe.settingsModels(view) }
        case "shotsettingspersonal": return { view in await DebugShotProbe.settingsPersonal(view) }
        case "shotsettingsmusic": return { view in await DebugShotProbe.settingsMusic(view) }
        case "shothelp": return { view in await DebugShotProbe.help(view) }
        case "shotconversation": return { view in await DebugShotProbe.conversation(view) }
        case "shotweather": return { view in await DebugShotProbe.weather(view) }
        case "shotreminders": return { view in await DebugShotProbe.reminders(view) }
        case "shotcalendar": return { view in await DebugShotProbe.calendar(view) }
        case "shotplaces": return { view in await DebugShotProbe.places(view) }
        case "shotcode": return { view in await DebugShotProbe.code(view) }
        case "shotscan": return { view in await DebugShotProbe.scanner(view) }
        case "shotscanreminder": return { view in await DebugShotProbe.scannerReminder(view) }
        case "shotpricewatch": return { view in await DebugShotProbe.priceWatch(view) }
        case "shotpricewatchhit": return { view in await DebugShotProbe.priceWatchHit(view) }
        case "shotbriefing": return { view in await DebugShotProbe.briefing(view) }
        case "shotresearchfollowup": return { view in await DebugShotProbe.researchFollowup(view) }
        case "shotresearchsourcecheck": return { view in await DebugShotProbe.researchSourceCheck(view) }
        case "shotimagegeneration": return { view in await DebugShotProbe.imageGeneration(view) }
        case "shotphotoediting": return { view in await DebugShotProbe.photoEditing(view) }
        case "shotphotogallery": return { view in await DebugShotProbe.photoGallery(view) }
        case "shotpricecomparison": return { view in await DebugShotProbe.priceComparison(view) }
        case "shottimer": return { view in await DebugShotProbe.timer(view) }
        case "shotmusic": return { view in await DebugShotProbe.music(view) }
        case "shotmessage": return { view in await DebugShotProbe.message(view) }
        case "shotcall": return { view in await DebugShotProbe.call(view) }
        case "shotfiles": return { view in await DebugShotProbe.fileReading(view) }
        case "shottranslation": return { view in await DebugShotProbe.translation(view) }
        case "shotmemory": return { view in await DebugShotProbe.memory(view) }
        case "shottime": return { view in await DebugShotProbe.time(view) }
        case "shotmultitask": return { view in await DebugShotProbe.multiTask(view) }
        case "shotreadaloud": return { view in await DebugShotProbe.readAloud(view) }
        case "shothistoryundo": return { view in await DebugShotProbe.historyUndo(view) }
        case "shotlistening": return { view in await DebugShotProbe.listening(view) }
        case "shotstop": return { view in await DebugShotProbe.stopRun(view) }
        default: return nil
        }
    }

    static func flowTest(named name: String) -> (@MainActor (ChatView) async -> Void)? {
        if let shot = shotTest(named: name) { return shot }
        if let extra = extraFlowTest(named: name) { return extra }
        switch name {
        case "sweep": return { view in await view.runSweep() }
        case "appstatus": return { view in await DebugAppStatusProbe.run(view) }
        case "makefixtures": return { view in await view.makeFixtures() }
        case "picsweep": return { view in await view.runPictureSweep() }
        case "stepsweep": return { view in await DebugStepProbe.sweep(view) }
        case "combosweep": return { view in await DebugComboProbe.sweep(view) }
        case "calaccess": return { view in await DebugCalendarAccessProbe.sweep(view) }
        case "gwencleanup": return { view in await DebugChainFixtures.cleanup(view) }
        case "turnsweep": return { view in await DebugTurnProbe.sweep(view) }
        case "wishsweep": return { view in await DebugWishProbe.sweep(view) }
        case "voicesignal": return { view in await DebugVoiceProbe.run(view) }
        case "voicelist": return { _ in await DebugVoiceProbe.listVoices() }
        case "personalvoice": return { view in await DebugVoiceProbe.personalVoice(view) }
        case "voicewords": return { view in await DebugVoiceProbe.measureWords(view) }
        case "voicequiet": return { view in await DebugVoiceProbe.quietRecognition(view) }
        case "voicelong": return { view in await DebugVoiceProbe.longDictation(view) }
        case "voiceoff": return { view in await DebugVoiceProbe.listenOffWords(view) }
        case "voiceoffflow": return { view in await DebugVoiceProbe.listenOffFlow(view) }
        case "sirisettings": return { view in await DebugVoiceProbe.settingsShots(view) }
        case "speaker": return { view in await DebugSpeakerProbe.run(view) }
        case "backgroundlisten": return { view in await DebugBackgroundListenProbe.run(view) }
        case "listenroute": return { view in await DebugListenRouteProbe.run(view) }
        case "routeswitch": return { view in await DebugRouteSwitchProbe.run(view) }
        case "routeyield": return { view in await DebugRouteYieldProbe.run(view) }
        case "listenbutton": return { view in await DebugListenButtonProbe.run(view) }
        case "wishstopp": return { view in await DebugWishProbe.stop(view) }
        case "wishrouting": return { view in await DebugWishRoutingProbe.sweep(view) }
        case "chainparallel": return { view in await DebugChainParallelProbe.run(view) }
        case "llmcompare": return { view in await DebugWishRoutingProbe.llmComparison(view) }
        case "wishplaner": return { view in await DebugWishRoutingProbe.plannerDates(view) }
        case "picturesplit": return { view in await DebugWishRoutingProbe.pictureChain(view) }
        case "picturedit": return { view in await DebugWishRoutingProbe.editChain(view) }
        case "picturesteps": return { view in await DebugWishRoutingProbe.editSteps(view) }
        case "callroute": return { view in await DebugCallProbe.routing(view) }
        case "callflow": return { view in await DebugCallProbe.flow(view) }
        case "calllink": return { view in await DebugCallProbe.links(view) }
        case "callcontacts": return { view in await DebugCallProbe.contacts(view) }
        case "calldialer": return { view in await DebugCallProbe.dialer(view) }
        case "soundcatalog": return { view in await DebugSoundProbe.catalog(view) }
        default: return nil
        }
    }

    private static func extraFlowTest(named name: String) -> (@MainActor (ChatView) async -> Void)? {
        switch name {
        case "clockroute": return { view in await DebugClockProbe.routing(view) }
        case "clockflow": return { view in await DebugClockProbe.flow(view) }
        case "musicroute": return { view in await DebugMusicProbe.routing(view) }
        case "musicflow": return { view in await DebugMusicProbe.flow(view) }
        case "musiclibrary": return { view in await DebugMusicProbe.library(view) }
        case "musiccatalog": return { view in await DebugMusicProbe.catalog(view) }
        case "spotifycheck": return { view in await DebugMusicProbe.spotify(view) }
        case "musicmix": return { view in await DebugMusicProbe.mix(view) }
        case "smsroute": return { view in await DebugMessageProbe.routing(view) }
        case "smsflow": return { view in await DebugMessageProbe.flow(view) }
        case "smscheck": return { view in await DebugMessageProbe.check(view) }
        case "smslanguage": return { view in await DebugMessageProbe.language(view) }
        case "reminderroute": return { view in await DebugReminderProbe.routing(view) }
        case "reminderflow": return { view in await DebugReminderProbe.flow(view) }
        case "reminderlive": return { _ in await DebugReminderProbe.live() }
        case "reminderdecode": return { _ in await DebugReminderProbe.decode() }
        case "reminderlists": return { _ in await DebugReminderProbe.lists() }
        case "memoryroute": return { _ in await DebugMemoryProbe.routing() }
        case "memorystore": return { _ in await DebugMemoryProbe.store() }
        case "historyroute": return { _ in await DebugHistoryProbe.routing() }
        case "structuredtools": return { _ in await DebugStructuredProbe.run() }
        case "structuredlive": return { view in await DebugStructuredProbe.live(view) }
        case "weatherroute": return { view in await DebugWeatherProbe.routing(view) }
        case "scanroute": return { view in await DebugScanProbe.routing(view) }
        case "scanflow": return { view in await DebugScanProbe.flow(view) }
        case "scanchat": return { view in await DebugScanProbe.chat(view) }
        case "weatherdecode": return { _ in await DebugWeatherProbe.decode() }
        case "weatherflow": return { _ in await DebugWeatherProbe.flow() }
        case "weatherchat": return { view in await DebugWeatherProbe.chat(view) }
        case "weathercard": return { view in await DebugWeatherCardProbe.run(view) }
        case "gallerybar": return { view in await DebugGalleryProbe.run(view) }
        case "codecard": return { view in await DebugCodeCardProbe.run(view) }
        case "setpanels": return { view in await DebugSettingsPanelsProbe.run(view) }
        case "macparts": return { view in await DebugMacPartsProbe.run(view) }
        case "timerroute": return { view in await DebugTimerProbe.routing(view) }
        case "timerflow": return { view in await DebugTimerProbe.flow(view) }
        case "timerlive": return { _ in await DebugTimerProbe.live() }
        case "readaloudroute": return { view in await DebugReadAloudProbe.routing(view) }
        case "readaloudflow": return { view in await DebugReadAloudProbe.flow(view) }
        case "codeguard": return { view in await view.runCodeGuardProbe() }
        case "searchonce": return { view in await view.runSearchOnceProbe() }
        case "sourcecheckbg": return { view in await DebugSourceCheckProbe.run(view) }
        case "sourceretry": return { view in await DebugSourceRetryProbe.run(view) }
        case "citationreview": return { view in await DebugCitationReviewProbe.run(view) }
        case "detailfollowup": return { view in await DebugDetailProbe.run(view) }
        case "chiptap": return { view in await DebugChipTapProbe.seed(view) }
        case "chipreal": return { view in await DebugChipTapProbe.real(view) }
        case "chipblank": return { view in view.store.newConversation() }
        case "chiptouch": return { view in await DebugChipTapProbe.touch(view) }
        case "exportprobe": return { view in await view.runExportProbe() }
        case "capsprobe": return { view in await view.runCapabilityProbe() }
        case "modelpick": return { view in await ModelPickProbe.run(view) }
        case "viewerprobe": return { view in await view.runViewerProbe() }
        case "airdropprobe": return { view in await view.runAirDropProbe() }
        case "menushow": return { view in await view.showAttachMenu() }
        case "settingshow": return { view in await view.showSettingsSheet() }
        case "appearanceswitch": return { view in await view.appearanceSwitch() }
        case "historyshot": return { view in await view.showHistoryWithSamples() }
        case "camtrans": return { view in await view.cameraTransition() }
        case "camsession": return { view in await view.cameraAudioSession() }
        case "camflow": return { view in await view.cameraSendFlow() }
        case "followup": return { view in await view.followUpEdits() }
        case "tripleedit": return { view in await view.repeatedEdits(marker: flowTestEditImage) }
        case "bigedit": return { view in await view.repeatedEdits(marker: flowTestBigImage) }
        case "editbig": return { view in
            await view.openBigConversation()
            await view.attachAndEdit(flowTestBigImage)
        }
        default: return nil
        }
    }

    @MainActor func withScreenAwake<T>(_ work: @MainActor () async -> T) async -> T {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        return await work()
    }

    func conversationHolding(output file: String) -> Conversation? {
        store.conversations.first { conversation in
            conversation.messages.contains { message in (message.outImages ?? []).contains { $0.file == file } }
        }
    }

    private func heavyConversation() -> Conversation? {
        store.conversations.first { $0.messages.count > 20 }
    }

    @MainActor private func showAttachMenu() async {
        store.newConversation()
        try? await Task.sleep(for: .milliseconds(600))
        attachMenu = true
    }

    @MainActor private func showSettingsSheet() async {
        showSettings = true
        try? await Task.sleep(for: .seconds(2))
    }

    @MainActor private func appearanceSwitch() async {
        let start = settings.appearance
        showSettings = true
        try? await Task.sleep(for: .seconds(4))
        settings.appearance = start == .dark ? .light : .dark
        try? await Task.sleep(for: .seconds(8))
        settings.appearance = start
        try? await Task.sleep(for: .seconds(3))
        showSettings = false
    }

    @MainActor private func showHistoryWithSamples() async {
        seedHistorySamples()
        showHistory = true
        try? await Task.sleep(for: .seconds(2))
    }

    @MainActor private func seedHistorySamples() {
        let samples: [(question: String, answer: String, sources: [WebSource])] = [
            ("Read what stands on my receipt photo",
             "On the receipt I can read: 2 × Flat White, 1 × Cheesecake, table 7 — "
             + "total €14.80, paid by card at 2:32 PM.",
             []),
            ("Translate \"I will be late, please start without me\" into French",
             "« Je serai en retard, commencez sans moi. » That is the polite form; among friends "
             + "you would say « Je vais être en retard, commence sans moi. »",
             []),
            ("Compare the prices of a MacBook Pro 14-inch and a 16-inch",
             "For the M5 Pro with 24 GB and 512 GB the shops currently ask:\n\n"
             + "**MacBook Pro 14-inch**\n1. Amazon — €2,299 [1]\n2. MediaMarkt — €2,349 [2]\n\n"
             + "**MacBook Pro 16-inch**\n1. Amazon — €2,799 [1]\n2. Cyberport — €2,849 [3]\n\n"
             + "The 16-inch costs about €500 more; Amazon has the cheapest offer for both sizes.",
             [WebSource(title: "MacBook Pro 14-inch M5", url: "https://www.amazon.de/",
                        domain: "www.amazon.de"),
              WebSource(title: "MacBook Pro 14-inch bei MediaMarkt", url: "https://www.mediamarkt.de/",
                        domain: "www.mediamarkt.de"),
              WebSource(title: "MacBook Pro 16-inch bei Cyberport", url: "https://www.cyberport.de/",
                        domain: "www.cyberport.de")]),
            ("Which are the three largest cities in Germany?",
             "By population, the three largest cities in Germany are:\n\n"
             + "1. **Berlin** — about 3.9 million people [1]\n"
             + "2. **Hamburg** — about 1.9 million people [1]\n"
             + "3. **Munich** — about 1.5 million people [2]\n\n"
             + "Berlin has grown the most over the past decade; the top three itself has not changed.",
             [WebSource(title: "Current population of the largest German cities",
                        url: "https://www.destatis.de/EN/Themes/Society-Environment/Population/"
                        + "Current-Population/Tables/liste-current-population-cities.html",
                        domain: "www.destatis.de"),
              WebSource(title: "List of cities in Germany by population",
                        url: "https://en.wikipedia.org/wiki/List_of_cities_in_Germany_by_population",
                        domain: "en.wikipedia.org"),
              WebSource(title: "Largest cities in Germany",
                        url: "https://www.statista.com/statistics/261690/largest-cities-in-germany/",
                        domain: "www.statista.com")]),
        ]
        for sample in samples {
            store.newConversation()
            guard let id = store.currentID else { continue }
            store.appendMessage(ChatMessage(role: .user, text: sample.question), to: id)
            store.appendAssistant(sample.answer, model: "qwen3.8-flash", elapsed: 3.4, to: id,
                                  sources: sample.sources.isEmpty ? nil : sample.sources)
        }
    }

    @MainActor private func cameraTransition() async {
        guard let conv = heavyConversation() else {
            flowLog.error("TEST no heavy conv")
            return
        }
        store.currentID = conv.id
        try? await Task.sleep(for: .milliseconds(1500))
        guard let shot = await flowTestPicture() else { return }
        for round in 1...ProbeRounds.maximum {
            let duringDismissal = round <= 3
            flowMark("CAMTRANS run=\(round) during=\(duringDismissal) present")
            inputFocused = true
            try? await Task.sleep(for: .milliseconds(1200))
            CameraPresenter.shared.present()
            try? await Task.sleep(for: .milliseconds(3500))
            CameraPresenter.shared.dismissPresented()
            if !duringDismissal {
                try? await Task.sleep(for: .milliseconds(1200))
            }
            pendingImages = [PendingPicture(image: shot, file: nil)]
            try? await Task.sleep(for: .milliseconds(4000))
            flowMark("CAMTRANS run=\(round) attached pending=\(pendingImages.count)")
            try? await Task.sleep(for: .milliseconds(3000))
            pendingImages = []
            try? await Task.sleep(for: .milliseconds(1500))
        }
        flowMark("CAMTRANS all done")
    }

    @MainActor private func cameraAudioSession() async {
        let report = SweepReport(file: "cam_session.txt")
        report.add("VOR_DER_KAMERA", Self.audioState(view: self))
        CameraPresenter.shared.present()
        try? await Task.sleep(for: .milliseconds(5000))
        report.add("KAMERA_OFFEN", Self.audioState(view: self))
        CameraPresenter.shared.dismissPresented()
        try? await Task.sleep(for: .milliseconds(1500))
        report.add("NACH_DISMISS_1s", Self.audioState(view: self))
        try? await Task.sleep(for: .milliseconds(4500))
        report.add("NACH_DISMISS_6s", Self.audioState(view: self))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? await Task.sleep(for: .milliseconds(1500))
        report.add("NACH_FREIGABE", Self.audioState(view: self))
        flowLog.info("CAMSESSION fertig")
    }

    @MainActor private static func audioState(view: ChatView) -> String {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: "+")
        return "kat=\(session.category.rawValue) mode=\(session.mode.rawValue) "
            + "eingangskanale=\(session.inputNumberOfChannels) route=\(inputs.isEmpty ? "keine" : inputs) "
            + "rate=\(Int(session.sampleRate)) andere_audio=\(session.isOtherAudioPlaying) "
            + "recorder=\(view.probeRecorderActive) voice=\(view.probeVoiceState)"
    }

    @MainActor private func cameraSendFlow() async {
        guard let img = await flowTestPicture() else { return }
        for run in 1...flowTestRounds {
            flowLog.info("CAMFLOW run=\(run) begin")
            store.newConversation()
            try? await Task.sleep(for: .milliseconds(600))
            inputFocused = true
            pendingImages = [PendingPicture(image: img, file: nil)]
            try? await Task.sleep(for: .milliseconds(1500))
            input = "\(PictureProbe.lighten) \(run)"
            await send()
            flowLog.info("CAMFLOW run=\(run) send returned")
            try? await Task.sleep(for: .milliseconds(6000))
        }
        flowLog.info("camflow all done")
    }

    @MainActor private func followUpEdits() async {
        guard let conv = conversationHolding(output: flowTestEditImage) else {
            flowLog.error("TEST no edit conv")
            return
        }
        store.currentID = conv.id
        try? await Task.sleep(for: .milliseconds(1500))
        for run in 1...flowTestRounds {
            flowLog.info("FOLLOWUP run=\(run) begin")
            let t0 = ContinuousClock.now
            input = "Bitte realitätsnaher mit Bränden und Rauch, Durchlauf \(run)"
            await send()
            flowLog.info("FOLLOWUP run=\(run) send returned ms=\(msOf(t0.duration(to: .now)))")
            try? await Task.sleep(for: .milliseconds(3000))
        }
        flowLog.info("followup all done")
    }

    @MainActor private func repeatedEdits(marker: String) async {
        guard let conv = conversationHolding(output: marker) else {
            flowLog.error("TEST no edit conv")
            return
        }
        store.currentID = conv.id
        flowLog.info("TRIPLE conv msgs=\(conv.messages.count)")
        try? await Task.sleep(for: .milliseconds(1500))
        for run in 1...flowTestRounds {
            flowLog.info("TRIPLE run=\(run) begin")
            let pool = conv.messages.flatMap(\.pictures)
            guard let candidate = pool.last(where: { store.media.data(for: $0) != nil }) ?? pool.last else {
                flowLog.error("TRIPLE run=\(run) no candidate")
                break
            }
            let t0 = ContinuousClock.now
            attachForEditing(candidate)
            _ = await ProbeWait.until(5) { !pendingImages.isEmpty }
            flowLog.info("TRIPLE run=\(run) attached ms=\(msOf(t0.duration(to: .now)))")
            input = PictureProbe.lighten
            await send()
            flowLog.info("TRIPLE run=\(run) send returned")
            try? await Task.sleep(for: .milliseconds(4000))
        }
        flowLog.info("TRIPLE all done")
    }

    @MainActor private func openBigConversation() async {
        guard let conv = conversationHolding(output: flowTestBigImage) else {
            flowLog.error("TEST no big conv")
            return
        }
        store.currentID = conv.id
        try? await Task.sleep(for: .milliseconds(2200))
    }

    @MainActor private func attachAndEdit(_ name: String) async {
        let all = store.conversations.flatMap { conversation in conversation.messages.flatMap(\.pictures) }
        guard let att = all.first(where: { $0.file == name }) ?? all.first ?? lastImageCandidate() else { return }
        flowLog.info("TEST step1 attachForEditing file=\(name, privacy: .public)")
        attachForEditing(att)
        _ = await ProbeWait.until(5) { !pendingImages.isEmpty }
        guard !pendingImages.isEmpty else {
            flowLog.error("TEST no pending image")
            return
        }
        flowLog.info("TEST step2 input+send")
        input = PictureProbe.lighten
        await send()
        flowLog.info("TEST step3 send returned")
    }
}
#endif
