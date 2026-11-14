#if DEBUG
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum ProviderProbe {
    static let reportFile = "provider_probe.txt"

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
        let unused = ProviderID.allCases.filter { $0 != originalProvider }
        note("MARKE", "providerprobe-v1")
        note("AKTIV", "anbieter=\(originalProvider.rawValue) chat=\(originalProfile.chatModel) "
             + "vision=\(originalProfile.visionModel.isEmpty ? "-" : originalProfile.visionModel) "
             + "bild=\(originalProfile.imageModel.isEmpty ? "-" : originalProfile.imageModel) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-") "
             + "altlasten=\(SettingsKey.legacyKeys.filter { UserDefaults.standard.object(forKey: $0) != nil })")
        note("UEBERSPRUNGEN", "anbieter=\(unused.map(\.rawValue).joined(separator: ",")) "
             + "grund=nicht_aktiver_anbieter")

        await inspect(originalProvider, settings: settings, note: note)
        if settings.isConfigured(for: originalProvider), !originalProfile.chatModel.trimmed.isEmpty,
           originalProfile.needsDiscovery(originalProfile.chatModel,
                                          encoding: originalProvider.descriptor.thinkingEncoding) {
            let started = ContinuousClock.now
            let found = await originalProvider.descriptor.modelDiscoverer
                .discover(baseURL: settings.baseURL(for: originalProvider),
                          key: settings.key(for: originalProvider),
                          models: [originalProfile.chatModel])
            let caps = found[originalProfile.chatModel] ?? ModelCapabilities()
            note("SONDE_\(originalProvider.rawValue)", "offen=1 erkannt=\(found.count) "
                 + "ms=\(msOf(started.duration(to: .now))) modell=\(originalProfile.chatModel) "
                 + "vision=\(caps.vision.rawValue) denkstufen=\(caps.thinking.levels.map(\.rawValue).joined(separator: ","))")
        } else {
            note("SONDE_\(originalProvider.rawValue)",
                 "uebersprungen modell=\(originalProfile.chatModel.isEmpty ? "-" : originalProfile.chatModel) "
                 + "grund=\(settings.isConfigured(for: originalProvider) ? "faehigkeiten_bekannt" : "kein_schluessel")")
        }
        if originalProvider == .qwenCloud { noteQwenMatrix(note) }
        if originalProvider == .deepSeek { noteDeepSeek(note) }
        noteSpeech(settings: settings, note: note)
        note("SCREEN", "uebersprungen: keine konfigurationsaenderung")

        let keysNow = ProviderID.allCases.map { settings.key(for: $0) }
        note("RUNDLAUF", "anbieter=\(settings.provider.rawValue) "
             + "verbindungen_unveraendert=\(settings.connections == originalConnections) "
             + "keys_unveraendert=\(keysNow == originalKeys) "
             + "profil_aktiv_unveraendert=\(settings.profile(of: originalProvider) == originalProfile) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-")")
        flowLog.info("PROVIDERPROBE fertig ohne aenderung")
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
        guard originalProvider == .deepSeek else {
            note("UEBERSPRUNGEN", "anbieter=\(originalProvider.rawValue) grund=nicht_aktiver_anbieter")
            flowLog.info("DEEPSEEKPROBE uebersprungen")
            return
        }

        noteDeepSeek(note)
        await inspect(.deepSeek, settings: settings, note: note)

        if settings.isConfigured(for: .deepSeek) {
            let profile = settings.profile(of: .deepSeek)
            let thinking = profile.capabilities(for: profile.chatModel).thinking
            note("MODELLE_deepseek", "nicht_geladen=true anzahl=\(profile.availableModels.count) "
                 + "chat=\(profile.chatModel) vision=\(profile.visionModel.isEmpty ? "-" : profile.visionModel) "
                 + "vision_liste=\(profile.visionCandidates.count) "
                 + "noch_offen=\(profile.modelsNeedingCaps(encoding: .openAI).count)")
            note("DENKEN_deepseek", "kodierung=\(thinking.encoding.rawValue) "
                 + "geprueft=\(thinking.probed) stufen=\(thinking.levels.map(\.rawValue).joined(separator: ",")) "
                 + "abschaltbar=\(thinking.canSwitchOff) "
                 + "angebot=\(thinking.offeredLevels.map(\.rawValue).joined(separator: ",")) "
                 + "aus=\(thinking.directive(for: .off).bodyEntries) "
                 + "mittel=\(thinking.directive(for: .medium).bodyEntries) "
                 + "vision=\(profile.capabilities(for: profile.chatModel).vision.rawValue)")
        } else {
            note("MODELLE_deepseek", "uebersprungen kein key")
        }
        note("SCREEN_deepseek", "uebersprungen: keine konfigurationsaenderung")

        note("RUNDLAUF", "anbieter=\(settings.provider.rawValue) "
             + "verbindungen_unveraendert=\(settings.connections == originalConnections) "
             + "key_unveraendert=\(settings.key(for: .deepSeek) == key) "
             + "gespeichert=\(UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "-")")
        flowLog.info("DEEPSEEKPROBE fertig ohne aenderung")
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
        guard !profile.chatModel.trimmed.isEmpty else {
            note("CHAT_\(id.rawValue)", "uebersprungen kein modell")
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
            do {
                let balance = try await reporter.accountBalance(key: key)
                let parts = balance.entries.map { "\($0.total) \($0.currency)" }
                note("GUTHABEN_\(id.rawValue)", parts.joined(separator: " · "))
            } catch {
                note("GUTHABEN_\(id.rawValue)", "FEHLER \(error.localizedDescription)")
            }
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
#endif
