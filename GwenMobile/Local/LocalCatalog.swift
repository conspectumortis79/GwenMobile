import GwenMobileKit
import Foundation

enum LocalModelFamily: String, CaseIterable, Codable, Sendable {
    case gemma
    case qwen
    case other
}

enum LocalModelSource: String, Codable, Hashable, Sendable {
    case builtIn
    case huggingFace
}

struct LocalModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let family: LocalModelFamily
    let bytes: Int64
    let minRamGB: Int
    let context: String
    let vision: Bool
    let tools: Bool
    var source: LocalModelSource = .builtIn
    var parameterBillions: Double? = nil
    var quantization: String? = nil
}

enum LocalCatalog {
    private static let dynamic = LockedValue<[String: LocalModelChoice]>([:])

    static func register(_ choices: [LocalModelChoice]) {
        dynamic.set(Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    static func choice(for id: String) -> LocalModelChoice? {
        if let installed = installedFallback(id) { return installed }
        return dynamic.current[id]
    }

    private static func installedFallback(_ id: String) -> LocalModelChoice? {
        let files = LocalModelFiles()
        guard let manifest = files.manifest(for: id), manifest.repo == id,
              files.isInstalled(id) else { return nil }
        return fallback(manifest: manifest, id: id)
    }

    static func fallback(manifest: LocalModelManifest, id: String) -> LocalModelChoice {
        let bytes = manifest.bytes
        return LocalModelChoice(id: id,
                                name: manifest.name ?? id.split(separator: "/").last.map(String.init) ?? id,
                                family: manifest.family ?? .other,
                                bytes: bytes,
                                minRamGB: LocalMemory.minRamGB(for: bytes),
                                context: manifest.context ?? "-",
                                vision: manifest.vision ?? visionFromConfig(id),
                                tools: manifest.tools ?? true,
                                source: manifest.source ?? .huggingFace,
                                parameterBillions: manifest.parameterBillions,
                                quantization: manifest.quantization)
    }

    private static func visionFromConfig(_ id: String) -> Bool {
        let url = LocalModelFiles().directory(for: id).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let architectures = object["architectures"] as? [String] ?? []
        if architectures.contains(where: {
            $0.contains("ConditionalGeneration") || $0.contains("Vision") || $0.contains("VL")
        }) {
            return true
        }
        let modelType = object["model_type"] as? String ?? ""
        return ["gemma3", "gemma4", "gemma4_unified", "qwen2_vl", "qwen2_5_vl",
                "qwen3_vl", "qwen3_vl_moe", "qwen3_5", "qwen3_5_moe", "idefics3",
                "smolvlm", "fastvlm", "pixtral", "mistral3", "lfm2_vl", "glm_ocr",
                "muse_glimmer"].contains(modelType)
    }
}
