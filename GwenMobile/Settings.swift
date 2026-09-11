import Foundation
import Security

enum SettingsKey {
    static let language = "language"
}

struct QwenEndpoint: Identifiable, Hashable {
    let url: String
    let de: String
    let en: String
    var id: String { url }
    var label: String { L.lang == .de ? de : en }
}

extension AppSettings {
    static let knownEndpoints: [QwenEndpoint] = [
        QwenEndpoint(url: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
                     de: "Token-Plan (Singapur)", en: "Token Plan (Singapore)"),
        QwenEndpoint(url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                     de: "Qwen Cloud International (Singapur)", en: "Qwen Cloud International (Singapore)"),
        QwenEndpoint(url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                     de: "China (Peking)", en: "China (Beijing)"),
        QwenEndpoint(url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1",
                     de: "USA (Virginia)", en: "US (Virginia)"),
        QwenEndpoint(url: "https://<WorkspaceId>.eu-central-1.maas.aliyuncs.com/compatible-mode/v1",
                     de: "EU (Frankfurt) — Workspace-ID einsetzen", en: "EU (Frankfurt) — insert Workspace-ID"),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    let defaultBaseURL: String
    let defaultChatModel = "qwen3.8-flash"
    let defaultVisionModel = "qwen3.8-max"
    let defaultImageModel = "wan2.7-image"
    let defaultAudioModel = "qwen-audio-3.0-realtime-plus"

    @Published var baseURL: String { didSet { d.set(baseURL, forKey: "baseURL") } }
    @Published var chatModel: String { didSet { d.set(chatModel, forKey: "chatModel") } }
    @Published var visionModel: String { didSet { d.set(visionModel, forKey: "visionModel") } }
    @Published var imageModel: String { didSet { d.set(imageModel, forKey: "imageModel") } }
    @Published var audioModel: String { didSet { d.set(audioModel, forKey: "audioModel") } }
    @Published var ttsVoice: String { didSet { d.set(ttsVoice, forKey: "ttsVoice") } }
    @Published var speakAnswers: Bool { didSet { d.set(speakAnswers, forKey: "speakAnswers") } }
    @Published var apiKey: String { didSet { Self.scheduleKeySave(apiKey) } }
    private static var keySaveTask: Task<Void, Never>?

    private static func scheduleKeySave(_ value: String) {
        keySaveTask?.cancel()
        keySaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            keySaveTask = nil
            saveKey(value)
        }
    }

    static func flushKeySave() {
        guard let t = keySaveTask else { return }
        keySaveTask = nil
        t.cancel()
        saveKey(shared.apiKey)
    }
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: SettingsKey.language); L.apply(language) } }
    @Published var availableModels: [String] { didSet { d.set(availableModels, forKey: "availableModels") } }

    private init() {
        defaultBaseURL = AppSettings.knownEndpoints.first?.url ?? ""
        L.apply(L.persistedLanguage())
        baseURL = d.string(forKey: "baseURL") ?? ""
        chatModel = d.string(forKey: "chatModel") ?? ""
        visionModel = d.string(forKey: "visionModel") ?? ""
        imageModel = d.string(forKey: "imageModel") ?? ""
        audioModel = d.string(forKey: "audioModel") ?? ""
        ttsVoice = d.string(forKey: "ttsVoice") ?? "hannah"
        speakAnswers = d.bool(forKey: "speakAnswers")
        apiKey = Self.loadKey()
        language = L.lang
        availableModels = d.stringArray(forKey: "availableModels") ?? []
        Self.importSeedFile()
        if baseURL.isEmpty { baseURL = defaultBaseURL }
        if chatModel.isEmpty { chatModel = defaultChatModel }
        if visionModel.isEmpty { visionModel = defaultVisionModel }
        if imageModel.isEmpty { imageModel = defaultImageModel }
        if audioModel.isEmpty { audioModel = defaultAudioModel }
    }

    var isConfigured: Bool { !apiKey.isEmpty && !baseURL.isEmpty }

    private static func importSeedFile() {
        guard loadKey().isEmpty else { return }
        let url = StoragePaths().apiKeySeed
        guard let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        saveKey(key)
        try? FileManager.default.removeItem(at: url)
    }

    private static func saveKey(_ value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GwenMobile",
            kSecAttrAccount as String: keyAccountStatic,
        ]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GwenMobile",
            kSecAttrAccount as String: keyAccountStatic,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static let keyAccountStatic = "qwencloud_api_key"
}
