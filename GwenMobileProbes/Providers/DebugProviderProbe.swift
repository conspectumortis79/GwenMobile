@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum ProviderProbe {
    static let reportFile = "provider_probe.txt"
    static let scrollOffset: CGFloat = 640

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        func note(_ section: String, _ detail: String) {
            report.add(section, detail)
        }
        let settings = view.settings
        let originalProvider = settings.provider
        let originalConnections = settings.connections
        let originalProfile = settings.profile(of: originalProvider)
        let originalKeys = ProviderID.allCases.map { settings.key(for: $0) }
        note("MARKE", "providerprobe-v1")
        note("AKTIV", "anbieter=\(originalProvider.rawValue) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-") "
             + "altlasten=\(SettingsKey.legacyKeys.filter { UserDefaults.standard.object(forKey: $0) != nil })")

        for id in ProviderID.allCases {
            await inspect(id, settings: settings, note: note)
        }
        for id in ProviderID.allCases where settings.isConfigured(for: id) {
            let started = ContinuousClock.now
            let pending = settings.profile(of: id).modelsNeedingCaps(encoding: id.descriptor.thinkingEncoding)
            await settings.refreshModelCaps(for: settings.profile(of: id).textCandidates, of: id)
            let profile = settings.profile(of: id)
            let thinking = profile.capabilities(for: profile.chatModel).thinking
            note("DENKEN_NEU_\(id.rawValue)", "offen_vorher=\(pending.count) "
                 + "offen_nachher=\(profile.modelsNeedingCaps(encoding: id.descriptor.thinkingEncoding).count) "
                 + "ms=\(msOf(started.duration(to: .now))) modell=\(profile.chatModel) kodierung=\(thinking.encoding.rawValue) "
                 + "stufen=\(thinking.levels.map(\.rawValue).joined(separator: ",")) abschaltbar=\(thinking.canSwitchOff) "
                 + "angebot=\(thinking.offeredLevels.map(\.rawValue).joined(separator: ",")) "
                 + "aus=\(thinking.directive(for: .off).bodyEntries) mittel=\(thinking.directive(for: .medium).bodyEntries) "
                 + "vision=\(profile.capabilities(for: profile.chatModel).vision.rawValue) visionListe=\(profile.visionCandidates.count)")
        }
        noteQwenMatrix(note)
        noteDeepSeek(note)
        noteSpeech(settings: settings, note: note)
        await screenshots(view, settings: settings, note: note)

        settings.provider = originalProvider
        settings.connections = originalConnections
        try? await Task.sleep(for: .milliseconds(500))
        let keysNow = ProviderID.allCases.map { settings.key(for: $0) }
        note("RUNDLAUF", "anbieter=\(settings.provider.rawValue) "
             + "verbindungen_unveraendert=\(settings.connections == originalConnections) "
             + "keys_unveraendert=\(keysNow == originalKeys) "
             + "profil_aktiv_unveraendert=\(settings.profile(of: originalProvider) == originalProfile) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-")")
        flowLog.info("PROVIDERPROBE fertig")
    }

    static func runDeepSeek(_ view: ChatView) async {
        let report = SweepReport(file: "deepseek_probe.txt")
        func note(_ section: String, _ detail: String) {
            report.add(section, detail)
        }
        let settings = view.settings
        let originalProvider = settings.provider
        let originalConnections = settings.connections
        let key = settings.key(for: .deepSeek)
        note("MARKE", "deepseekprobe-v1")
        note("AKTIV", "anbieter=\(originalProvider.rawValue) "
             + "deepseek_konfiguriert=\(settings.isConfigured(for: .deepSeek)) key=\(mask(key)) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-")")

        noteDeepSeek(note)
        await inspect(.deepSeek, settings: settings, note: note)

        if settings.isConfigured(for: .deepSeek) {
            let started = ContinuousClock.now
            do {
                try await settings.reloadModels(of: .deepSeek)
                let profile = settings.profile(of: .deepSeek)
                let thinking = profile.capabilities(for: profile.chatModel).thinking
                note("MODELLE_deepseek", "anzahl=\(profile.availableModels.count) chat=\(profile.chatModel) "
                     + "vision=\(profile.visionModel.isEmpty ? "-" : profile.visionModel) "
                     + "vision_liste=\(profile.visionCandidates.count) "
                     + "noch_offen=\(profile.modelsNeedingCaps(encoding: .openAI).count) "
                     + "ms=\(msOf(started.duration(to: .now)))")
                note("DENKEN_NEU_deepseek", "kodierung=\(thinking.encoding.rawValue) "
                     + "geprueft=\(thinking.probed) stufen=\(thinking.levels.map(\.rawValue).joined(separator: ",")) "
                     + "abschaltbar=\(thinking.canSwitchOff) "
                     + "angebot=\(thinking.offeredLevels.map(\.rawValue).joined(separator: ",")) "
                     + "aus=\(thinking.directive(for: .off).bodyEntries) "
                     + "mittel=\(thinking.directive(for: .medium).bodyEntries) "
                     + "vision=\(profile.capabilities(for: profile.chatModel).vision.rawValue)")
            } catch {
                let status = (error as? APIError)?.status
                note("MODELLE_deepseek", "FEHLER status=\(status.map(String.init) ?? "-") "
                     + "meldung=\(TextLine.oneLine(error.localizedDescription, limit: 120)) "
                     + "ms=\(msOf(started.duration(to: .now)))")
            }
        } else {
            note("MODELLE_deepseek", "uebersprungen kein key")
        }
        await deepSeekScreens(view, settings: settings, note: note)

        settings.provider = originalProvider
        settings.connections = originalConnections
        try? await Task.sleep(for: .milliseconds(500))
        note("RUNDLAUF", "anbieter=\(settings.provider.rawValue) "
             + "verbindungen_unveraendert=\(settings.connections == originalConnections) "
             + "key_unveraendert=\(settings.key(for: .deepSeek) == key) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-")")
        flowLog.info("DEEPSEEKPROBE fertig")
    }

    private static func deepSeekScreens(_ view: ChatView, settings: AppSettings,
                                        note: (String, String) -> Void) async {
        settings.provider = .deepSeek
        view.showSettings = true
        _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController != nil }
        _ = await ProbeWait.until(5) {
            guard let sheet = Presenter.topViewController?.view else { return false }
            return textFields(in: sheet).contains { $0.isSecureTextEntry }
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard let window = Presenter.windowRootViewController?.view?.window else {
            note("SCREEN_deepseek", "kein Fenster")
            view.showSettings = false
            return
        }
        note("SCREEN_deepseek_oben", ViewerProbe.snapshot(window, named: "deepseek_probe_1.jpg"))
        await notePanel(window: window, section: "deepseek", filePrefix: "deepseek_probe", note: note)
        view.showSettings = false
        _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController == nil }
    }

    private static func notePanel(window: UIWindow, section: String, filePrefix: String,
                                  note: (String, String) -> Void) async {
        if let sheet = Presenter.topViewController?.view {
            let fields = textFields(in: sheet)
            note("FELDER_\(section)", fields.map {
                "sicher=\($0.isSecureTextEntry) zeichen=\($0.text?.count ?? -1) platzhalter=\($0.placeholder ?? "-")"
            }.joined(separator: " | "))
        }
        if let sheet = Presenter.topViewController?.view, let scroll = formScrollView(in: sheet) {
            let maxOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
            let target = min(maxOffset, scrollOffset)
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            _ = await ProbeWait.until(3) { abs(scroll.contentOffset.y - target) < 1 }
            note("SCREEN_\(section)_unten", ViewerProbe.snapshot(window, named: "\(filePrefix)_2.jpg")
                 + " inhalt=\(Int(scroll.contentSize.height))")
        } else {
            note("SCREEN_\(section)_unten", "kein Formular gefunden")
        }
    }

    private static func inspect(_ id: ProviderID, settings: AppSettings,
                                note: (String, String) -> Void) async {
        let descriptor = id.descriptor
        let key = settings.key(for: id)
        let profile = settings.profile(of: id)
        let caps = descriptor.capabilities
        let baseURL = settings.baseURL(for: id)
        note("KONFIG_\(id.rawValue)", "titel=\(descriptor.title) konfiguriert=\(settings.isConfigured(for: id)) "
             + "key=\(mask(key)) url=\(baseURL) chat=\(profile.chatModel) vision=\(profile.visionModel) "
             + "bild=\(profile.imageModel) modelle=\(profile.availableModels.count) "
             + "faehigkeiten=chat:\(caps.chat.rawValue),vision:\(caps.vision.rawValue),bild:\(caps.image.rawValue) "
             + "vorlageURL=\(descriptor.usesPresetURL(settings.connections)) platzhalter=\(descriptor.keyPlaceholder(settings.connections))")

        let thinking = profile.capabilities(for: profile.chatModel).thinking
        note("DENKEN_\(id.rawValue)", "modell=\(profile.chatModel) kodierung=\(thinking.encoding.rawValue) "
             + "bekannt=\(thinking.isKnown) geprueft=\(thinking.probed) stufen=\(thinking.levels.map(\.rawValue).joined(separator: ",")) "
             + "abschaltbar=\(thinking.canSwitchOff) angebot=\(thinking.offeredLevels.map(\.rawValue).joined(separator: ",")) "
             + "aus=\(thinking.directive(for: .off).bodyEntries) mittel=\(thinking.directive(for: .medium).bodyEntries) "
             + "vision=\(profile.capabilities(for: profile.chatModel).vision.rawValue) visionListe=\(profile.visionCandidates.count)")

        if var probe = HTTP.endpoint(baseURL, APIEndpoint.models).map({ URLRequest(url: $0) }) {
            descriptor.requestDecorator(settings.connections).decorate(&probe)
            note("HEADER_\(id.rawValue)", "titel=\(probe.value(forHTTPHeaderField: "X-OpenRouter-Title") ?? "-") "
                 + "xtitle=\(probe.value(forHTTPHeaderField: "X-Title") ?? "-") "
                 + "referer=\(probe.value(forHTTPHeaderField: "HTTP-Referer") ?? "-") "
                 + "sichtbarkeit=\(probe.value(forHTTPHeaderField: "X-OpenRouter-App-Visibility") ?? "-")")
        }

        let started = ContinuousClock.now
        do {
            let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
            let text = ModelFilter.textCandidates(models)
            note("MODELLE_\(id.rawValue)", "anzahl=\(models.count) text=\(text.count) "
                 + "erste=\(models.prefix(3).joined(separator: ",")) ms=\(msOf(started.duration(to: .now)))")
        } catch {
            let status = (error as? APIError)?.status
            let friendly = L.friendlyError(error.localizedDescription, status: status)
            note("MODELLE_\(id.rawValue)", "FEHLER status=\(status.map(String.init) ?? "-") "
                 + "meldung=\(friendly.message.prefix(120)) detail=\(friendly.detail) ms=\(msOf(started.duration(to: .now)))")
        }

        guard settings.isConfigured(for: id) else {
            note("CHAT_\(id.rawValue)", "uebersprungen kein key")
            return
        }
        let chatStarted = ContinuousClock.now
        do {
            let message = ChatMessage(role: .user, text: L.t("test_prompt"))
            let request = try QwenAPI.makeRequest(baseURL: baseURL, key: key, model: profile.chatModel,
                                                  messages: [message], imageData: [], stream: true,
                                                  thinking: profile.capabilities(for: profile.chatModel)
                                                      .thinking.directive(for: .off))
            var answer = ""
            for try await chunk in QwenAPI.streamText(req: request) { answer += chunk }
            note("CHAT_\(id.rawValue)", "modell=\(profile.chatModel) antwort=\(TextLine.oneLine(answer, limit: 60)) "
                 + "ms=\(msOf(chatStarted.duration(to: .now)))")
        } catch {
            let status = (error as? APIError)?.status
            let friendly = L.friendlyError(error.localizedDescription, model: profile.chatModel, status: status)
            note("CHAT_\(id.rawValue)", "FEHLER modell=\(profile.chatModel) status=\(status.map(String.init) ?? "-") "
                 + "meldung=\(friendly.message.prefix(120)) ms=\(msOf(chatStarted.duration(to: .now)))")
        }
        if let reporter = descriptor as? any AccountBalanceReporting {
            note("GUTHABEN_\(id.rawValue)", await reporter.accountBalance(key: key) ?? "nil")
        }
    }

    private static func noteQwenMatrix(_ note: (String, String) -> Void) {
        note("QWEN_URL_tokenPlan", QwenCloudConfig().baseURL)
        for region in QwenRegion.allCases {
            let config = QwenCloudConfig(billing: .payAsYouGo, region: region,
                                         workspace: region.needsWorkspace ? "llm-probe" : "")
            note("QWEN_URL_\(region.rawValue)", "\(config.baseURL) rueckweg=\(QwenEndpoints.config(matching: config.baseURL) == config)")
        }
        note("OPENAI_VORLAGEN", OpenAIPresets.all.map { "\($0.id)=\($0.url.isEmpty ? "-" : $0.url)" }.joined(separator: " "))
    }

    private static func noteDeepSeek(_ note: (String, String) -> Void) {
        let base = DeepSeekAPI.baseURL
        note("DEEPSEEK_URL", "base=\(base) "
             + "chat=\((try? HTTP.chatCompletionsURL(base))?.absoluteString ?? "-") "
             + "modelle=\(HTTP.endpoint(base, APIEndpoint.models)?.absoluteString ?? "-") "
             + "guthaben=\(HTTP.endpoint(base, DeepSeekAPI.balancePath)?.absoluteString ?? "-")")
        let sample = Data("""
        {"data":[
          {"id":"deepseek-flash","input_modalities":["text","image"],
           "effort":{"supported_levels":["low","high","max"],"default_level":"high"}},
          {"id":"deepseek-v4-pro","input_modalities":["text"],
           "effort":{"supported_levels":["high","max"]}}
        ]}
        """.utf8)
        guard let list = try? JSONDecoder().decode(DeepSeekModelList.self, from: sample) else {
            note("DEEPSEEK_KATALOG", "beispiel nicht lesbar")
            return
        }
        let caps = DeepSeekModelCatalog.capabilities(of: list.data,
                                                     for: ["deepseek-flash", "deepseek-v4-pro"])
        note("DEEPSEEK_KATALOG", caps.keys.sorted().map { id in
            let found = caps[id] ?? ModelCapabilities()
            return "\(id): stufen=\(found.thinking.levels.map(\.rawValue).joined(separator: ",")) "
                + "abschaltbar=\(found.thinking.canSwitchOff) aus=\(found.thinking.directive(for: .off).bodyEntries) "
                + "vision=\(found.vision.rawValue)"
        }.joined(separator: " | "))
    }

    private static func noteSpeech(settings: AppSettings, note: (String, String) -> Void) {
        let recognizer = SystemSpeechRecognizer(locale: settings.language.locale)
        note("SPRACHE_IOS", "erkennung_status=\(SystemSpeechRecognizer.authorizationStatus.rawValue) "
             + "verfuegbar=\(recognizer.isAvailable) "
             + "stimme=\(VoiceCatalog.defaultVoiceName(for: settings.language))")
    }

    private static func screenshots(_ view: ChatView, settings: AppSettings,
                                    note: (String, String) -> Void) async {
        for id in ProviderID.allCases {
            settings.provider = id
            view.showSettings = true
            _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController != nil }
            guard let window = Presenter.windowRootViewController?.view?.window else {
                note("SCREEN_\(id.rawValue)", "kein Fenster")
                continue
            }
            note("SCREEN_\(id.rawValue)_oben", ViewerProbe.snapshot(window, named: "provider_probe_\(id.rawValue)_1.jpg"))
            await notePanel(window: window, section: id.rawValue, filePrefix: "provider_probe_\(id.rawValue)",
                            note: note)
            view.showSettings = false
            _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController == nil }
        }
        await qwenRegionScreens(view, settings: settings, note: note)
    }

    private static func qwenRegionScreens(_ view: ChatView, settings: AppSettings,
                                          note: (String, String) -> Void) async {
        settings.provider = .qwenCloud
        settings.connections.qwenCloud = QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: "")
        view.showSettings = true
        _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController != nil }
        if let window = Presenter.windowRootViewController?.view?.window {
            note("SCREEN_qwen_eu", ViewerProbe.snapshot(window, named: "provider_probe_qwen_eu.jpg")
                 + " konfiguriert=\(settings.isConfigured) url=\(settings.baseURL)")
        }
        view.showSettings = false
        _ = await ProbeWait.until(5) { Presenter.windowRootViewController?.presentedViewController == nil }
    }

    private static func textFields(in root: UIView) -> [UITextField] {
        var found: [UITextField] = []
        func walk(_ candidate: UIView) {
            if let field = candidate as? UITextField { found.append(field) }
            candidate.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    static func formScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ candidate: UIView) {
            if let scroll = candidate as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height,
               scroll.bounds.height > (best?.bounds.height ?? 0) {
                best = scroll
            }
            candidate.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    private static func mask(_ key: String) -> String {
        guard !key.isEmpty else { return "leer" }
        return "\(key.prefix(6))…(\(key.count))"
    }
}
#endif
