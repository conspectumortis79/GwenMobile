import GwenMobileKit
import Foundation
import MLXLLM
import MLXVLM

enum HuggingFaceMLXError: LocalizedError {
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .invalidResponse: return L.t("local_model_hf_error")
        }
    }
}

struct HuggingFaceMLXCatalog: Sendable {
    static let maxCandidates = 24
    static let excludedWords = ["embedding", "embed", "reranker", "rerank", "draft", "mtp",
                                "speculative", "adapter", "lora", "gguf", "onnx", "pytorch",
                                "whisper", "audio", "diffusion", "ocr"]

    let session: URLSession

    init(session: URLSession = HuggingFaceMLXCatalog.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        LocalURLSession.ephemeral(requestTimeout: 30, resourceTimeout: 90, connectionsPerHost: 6)
    }

    func discover() async throws -> [LocalModelChoice] {
        let summaries = try await search()
        let candidates = summaries
            .filter(Self.passesBaseFilter)
            .sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
            .prefix(Self.maxCandidates)
        guard !candidates.isEmpty else { return [] }
        var details = [Detail?](repeating: nil, count: candidates.count)
        try await withThrowingTaskGroup(of: (Int, Detail?).self) { group in
            for (index, summary) in candidates.enumerated() {
                group.addTask { [self] in
                    (index, try? await detail(for: summary.id))
                }
            }
            for try await (index, detail) in group {
                details[index] = detail
            }
        }
        var choices: [LocalModelChoice] = []
        for (index, summary) in candidates.enumerated() {
            guard let detail = details[index], let choice = await choice(summary: summary, detail: detail)
            else { continue }
            choices.append(choice)
        }
        return choices.sorted {
            if $0.parameterBillions != $1.parameterBillions {
                return ($0.parameterBillions ?? 0) < ($1.parameterBillions ?? 0)
            }
            return $0.id < $1.id
        }
    }

    private func search() async throws -> [Summary] {
        var components = URLComponents(string: HuggingFaceHub.modelsAPI)
        components?.queryItems = [
            URLQueryItem(name: "author", value: "mlx-community"),
            URLQueryItem(name: "filter", value: "mlx"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "full", value: "true"),
        ]
        guard let url = components?.url else { throw HuggingFaceMLXError.invalidResponse }
        let data = try await load(url)
        return try JSONDecoder().decode([Summary].self, from: data)
    }

    private func detail(for repo: String) async throws -> Detail {
        guard let url = HuggingFaceHub.detailURL(for: repo) else {
            throw HuggingFaceMLXError.invalidResponse
        }
        let data = try await load(url)
        return try JSONDecoder().decode(Detail.self, from: data)
    }

    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("GwenMobile", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code < 400 else { throw HuggingFaceMLXError.http(code) }
        return data
    }

    func choice(summary: Summary, detail: Detail) async -> LocalModelChoice? {
        guard Self.passesBaseFilter(summary), !detail.isPrivate, !detail.gated.isTrue,
              detail.libraryName == "mlx" else { return nil }
        let parameterBillions = Self.parameterBillions(from: summary.id)
        let tags = Set((detail.tags ?? []) + (summary.tags ?? []))
        let pipeline = detail.pipelineTag ?? summary.pipelineTag
        let wantsVision = pipeline == "image-text-to-text" || tags.contains("mlx-vlm")
        let modelType = detail.config?.modelType
        let vlmSupported: Bool
        let llmSupported: Bool
        if let modelType {
            vlmSupported = await VLMTypeRegistry.shared.contains(modelType)
            llmSupported = await LLMTypeRegistry.shared.contains(modelType)
        } else {
            vlmSupported = false
            llmSupported = false
        }
        let isVision = wantsVision && vlmSupported
        let isText = !wantsVision && llmSupported
        guard isVision || isText else { return nil }
        let files = (detail.siblings ?? []).filter { HuggingFaceHub.isModelFile($0.rfilename) }
        guard files.contains(where: { $0.rfilename.hasSuffix(".safetensors") }),
              files.contains(where: { $0.rfilename == "config.json" }),
              files.contains(where: { $0.rfilename == "tokenizer.json" }) else { return nil }
        let bytes = files.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }
        guard bytes > 0 else { return nil }
        let context = Self.contextLabel(detail.config)
        let quantization = Self.quantization(tags: tags, config: detail.config)
        let name = summary.id.split(separator: "/").last.map(String.init) ?? summary.id
        return LocalModelChoice(id: summary.id,
                                name: name,
                                family: Self.family(summary.id),
                                bytes: bytes,
                                minRamGB: LocalMemory.minRamGB(for: bytes),
                                context: context,
                                vision: isVision,
                                tools: true,
                                source: .huggingFace,
                                parameterBillions: parameterBillions,
                                quantization: quantization)
    }

    static func parameterBillions(from name: String) -> Double? {
        let pattern = "(?i)([0-9]+(?:\\.[0-9]+)?)b(?![a-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(name.startIndex ..< name.endIndex, in: name)
        return regex.firstMatch(in: name, range: range).flatMap { match in
            guard let valueRange = Range(match.range(at: 1), in: name) else { return nil }
            return Double(name[valueRange])
        }
    }

    static func passesBaseFilter(_ summary: Summary) -> Bool {
        guard !summary.isPrivate, !summary.gated.isTrue,
              summary.libraryName == "mlx" else { return false }
        let tags = summary.tags ?? []
        guard tags.contains("mlx"), tags.contains("safetensors") else { return false }
        let lower = summary.id.lowercased()
        guard !excludedWords.contains(where: { lower.contains($0) }) else { return false }
        if let pipeline = summary.pipelineTag,
           pipeline != "text-generation", pipeline != "image-text-to-text" {
            return false
        }
        return true
    }

    static func family(_ id: String) -> LocalModelFamily {
        let lower = id.lowercased()
        if lower.contains("gemma") { return .gemma }
        if lower.contains("qwen") { return .qwen }
        return .other
    }

    private static func contextLabel(_ config: Config?) -> String {
        guard let positions = config?.maxPositionEmbeddings ?? config?.textConfig?.maxPositionEmbeddings,
              positions > 0 else { return "-" }
        if positions % 1024 == 0 {
            return "\(positions / 1024)K"
        }
        return "\(positions)"
    }

    private static func quantization(tags: Set<String>, config: Config?) -> String? {
        if tags.contains("4-bit") { return "4-bit" }
        if tags.contains("8-bit") { return "8-bit" }
        if tags.contains("6-bit") { return "6-bit" }
        if let bits = config?.quantizationConfig?.bits { return "\(bits)-bit" }
        return nil
    }
}

extension HuggingFaceMLXCatalog {
    struct FlexibleFlag: Decodable, Sendable {
        let isTrue: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                isTrue = value
            } else if let value = try? container.decode(String.self) {
                isTrue = value.lowercased() != "false"
            } else {
                isTrue = false
            }
        }
    }

    struct Summary: Decodable, Sendable {
        var id: String
        var libraryName: String?
        var tags: [String]?
        var pipelineTag: String?
        var downloads: Int?
        var gated: FlexibleFlag
        var isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case libraryName = "library_name"
            case tags
            case pipelineTag = "pipeline_tag"
            case downloads
            case gated
            case isPrivate = "private"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            libraryName = try container.decodeIfPresent(String.self, forKey: .libraryName)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            pipelineTag = try container.decodeIfPresent(String.self, forKey: .pipelineTag)
            downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
            gated = try container.decodeIfPresent(FlexibleFlag.self, forKey: .gated)
                ?? FlexibleFlag(isTrue: false)
            isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        }
    }

    struct Detail: Decodable, Sendable {
        var libraryName: String?
        var tags: [String]?
        var pipelineTag: String?
        var gated: FlexibleFlag
        var isPrivate: Bool
        var config: Config?
        var siblings: [Sibling]?

        enum CodingKeys: String, CodingKey {
            case libraryName = "library_name"
            case tags
            case pipelineTag = "pipeline_tag"
            case gated
            case isPrivate = "private"
            case config
            case siblings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            libraryName = try container.decodeIfPresent(String.self, forKey: .libraryName)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            pipelineTag = try container.decodeIfPresent(String.self, forKey: .pipelineTag)
            gated = try container.decodeIfPresent(FlexibleFlag.self, forKey: .gated)
                ?? FlexibleFlag(isTrue: false)
            isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
            config = try container.decodeIfPresent(Config.self, forKey: .config)
            siblings = try container.decodeIfPresent([Sibling].self, forKey: .siblings)
        }
    }

    struct Config: Decodable, Sendable {
        var modelType: String?
        var maxPositionEmbeddings: Int?
        var textConfig: TextConfig?
        var quantizationConfig: Quantization?

        enum CodingKeys: String, CodingKey {
            case modelType = "model_type"
            case maxPositionEmbeddings = "max_position_embeddings"
            case textConfig = "text_config"
            case quantizationConfig = "quantization_config"
        }
    }

    struct TextConfig: Decodable, Sendable {
        var maxPositionEmbeddings: Int?

        enum CodingKeys: String, CodingKey {
            case maxPositionEmbeddings = "max_position_embeddings"
        }
    }

    struct Quantization: Decodable, Sendable {
        var bits: Int?
    }

    struct Sibling: Decodable, Sendable {
        var rfilename: String
        var size: Int64?
    }
}

extension HuggingFaceMLXCatalog.FlexibleFlag {
    init(isTrue: Bool) {
        self.isTrue = isTrue
    }
}
