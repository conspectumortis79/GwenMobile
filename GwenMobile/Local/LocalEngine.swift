import GwenMobileKit
import CoreImage
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers

struct LocalEngineInfo: Sendable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var finishReason: String
}

enum LocalEngineEvent: Sendable {
    case text(String)
    case toolCall(LocalToolCall)
    case info(LocalEngineInfo)
}

enum LocalEngineError: LocalizedError {
    case notInstalled(String)
    case memory
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return L.t("local_error_not_installed")
        case .memory: return L.t("local_error_memory")
        case .unsupported(let model): return L.t("local_error_unsupported") + " " + model
        }
    }
}

struct LocalEngineMemory: Sendable, Equatable {
    var active: Int
    var available: Int64
    var mlxActive: Int
    var mlxPeak: Int
    var mlxCache: Int
}

actor LocalEngine {
    static let shared = LocalEngine()

    static let reasoning = ReasoningConfig(startDelimiter: "<|channel>thought",
                                           endDelimiter: "<channel|>",
                                           promptStrategy: .templateFlag(key: "enable_thinking",
                                                                         defaultOn: false),
                                           isSpecialToken: true)
    static let cacheLimit = 20 * 1024 * 1024

    private var container: ModelContainer?
    private var loadedModel: String?
    private var loadingModel: String?
    private var active = 0
    private var serialRunning = false
    private var serialWaiters: [CheckedContinuation<Void, Never>] = []

    func modelSnapshot() -> (loaded: String?, loading: String?) {
        (loadedModel, loadingModel)
    }

    func memoryReport() -> LocalEngineMemory {
        LocalEngineMemory(active: active, available: LocalMemory.available,
                          mlxActive: Memory.activeMemory, mlxPeak: Memory.peakMemory,
                          mlxCache: Memory.cacheMemory)
    }

    #if DEBUG
    func queueState() -> (queued: Int, running: Bool) {
        (serialWaiters.count, serialRunning)
    }
    #endif

    func run(_ request: LocalChatRequest) async throws -> LocalChatResult {
        var text = ""
        var calls: [LocalToolCall] = []
        var info: LocalEngineInfo?
        for try await event in stream(request) {
            switch event {
            case .text(let chunk):
                text += chunk
            case .toolCall(let call):
                calls.append(call)
            case .info(let value):
                info = value
            }
        }
        let reason = calls.isEmpty ? (info?.finishReason ?? "stop") : "tool_calls"
        return LocalChatResult(text: text, toolCalls: calls,
                               promptTokens: info?.promptTokens ?? 0,
                               completionTokens: info?.completionTokens ?? 0,
                               finishReason: reason)
    }

    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalEngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish(throwing: LocalEngineError.unsupported(request.model))
                    return
                }
                await self.acquire()
                var started = false
                do {
                    try Task.checkCancellation()
                    await self.begin()
                    started = true
                    await self.log("START", extra: "modell=\(request.model) nachrichten=\(request.messages.count) "
                                   + "werkzeuge=\(request.tools.count) max=\(request.maxTokens ?? 700) "
                                   + "denken=\(request.thinking)")
                    let container = try await self.load(request.model)
                    try Task.checkCancellation()
                    guard LocalMemory.hasGenerationRoom else {
                        await self.log("ABBRUCH", extra: "grund=speicher_vor_start frei=\(LocalMemory.available)")
                        throw LocalEngineError.memory
                    }
                    let request = Self.localRequest(request)
                    guard let last = request.messages.last else { throw LocalRequestError.noQuestion }
                    let parameters = Self.parameters(request)
                    await self.log("BILDER", extra: "letzte=\(last.images.count) "
                                   + "verlauf=\(request.messages.dropLast().reduce(0) { $0 + $1.images.count })")
                    let session = ChatSession(container,
                                              instructions: nil,
                                              history: request.messages.dropLast().map(Self.message),
                                              generateParameters: parameters,
                                              processing: UserInput.Processing(resize: CGSize(width: 512,
                                                                                              height: 512)),
                                              additionalContext: ["enable_thinking": request.thinking],
                                              tools: request.tools.isEmpty ? nil : request.tools)
                    let images = last.images.compactMap { CIImage(data: $0) }
                        .map { UserInput.Image.ciImage($0) }
                    var index = 0
                    let qwen = request.model == LocalModelConfigurations.qwen9BID
                    var filter = qwen
                        ? LocalThinkingFilter(start: "<think>", end: "</think>", primed: request.thinking)
                        : LocalThinkingFilter()
                    for try await generation in session.streamDetails(to: last.text, role: .user,
                                                                      images: images) {
                        try Task.checkCancellation()
                        guard LocalMemory.hasGenerationRoom else {
                            await self.log("ABBRUCH", extra: "grund=speicher_waehrend frei=\(LocalMemory.available)")
                            Memory.clearCache()
                            throw LocalEngineError.memory
                        }
                        switch generation {
                        case .chunk(let chunk):
                            let visible = filter.feed(chunk)
                            if !visible.isEmpty { continuation.yield(.text(visible)) }
                        case .toolCall(let call):
                            continuation.yield(.toolCall(LocalOpenAIResponse.toolCall(call, index: index)))
                            index += 1
                        case .info(let info):
                            let summary = Self.info(info)
                            flowMark("LOKAL TOKENS prompt=\(summary.promptTokens) "
                                     + "antwort=\(summary.completionTokens) grund=\(summary.finishReason)")
                            continuation.yield(.info(summary))
                        case .rejectedToolCall:
                            break
                        }
                    }
                    let tail = filter.finish()
                    if !tail.isEmpty { continuation.yield(.text(tail)) }
                    await self.log("ENDE", extra: "grund=fertig")
                    continuation.finish()
                } catch {
                    await self.log("FEHLER", extra: "text=\(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
                if started { await self.end() }
                await self.release()
                Memory.clearCache()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unloadIfIdle() {
        guard active == 0 else { return }
        let hadModel = container != nil || loadedModel != nil
        if hadModel { log("ENTLADEN", extra: "grund=idle") }
        container = nil
        loadedModel = nil
        if hadModel { Memory.clearCache() }
    }

    func unload() {
        let hadModel = container != nil || loadedModel != nil
        if hadModel { log("ENTLADEN", extra: "grund=anforderung") }
        container = nil
        loadedModel = nil
        if hadModel { Memory.clearCache() }
    }

    private func begin() {
        active += 1
    }

    private func end() {
        active = max(0, active - 1)
    }

    private func acquire() async {
        if !serialRunning {
            serialRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            serialWaiters.append(continuation)
        }
    }

    private func release() {
        if serialWaiters.isEmpty {
            serialRunning = false
            return
        }
        serialWaiters.removeFirst().resume()
    }

    private func load(_ model: String) async throws -> ModelContainer {
        if let container, loadedModel == model {
            log("WIEDERVERWENDEN", extra: "modell=\(model)")
            return container
        }
        log("LADEN", extra: "modell=\(model) vorhanden=\(loadedModel ?? "-")")
        loadingModel = model
        defer { loadingModel = nil }
        return try await Task { try await self.performLoad(model) }.value
    }

    private func performLoad(_ model: String) async throws -> ModelContainer {
        guard let choice = LocalCatalog.choice(for: model) else {
            throw LocalEngineError.unsupported(model)
        }
        let files = LocalModelFiles()
        guard files.isInstalled(model) else {
            throw LocalEngineError.notInstalled(model)
        }
        container = nil
        loadedModel = nil
        Memory.memoryLimit = LocalMemory.mlxLimit
        Memory.cacheLimit = Self.cacheLimit
        Memory.clearCache()
        guard LocalMemory.canFit(choice.bytes) else {
            throw LocalEngineError.memory
        }
        let downloader = LocalInstalledDownloader(files: files)
        let configuration = Self.configuration(for: model)
        let loaded: ModelContainer
        if choice.vision {
            loaded = try await VLMModelFactory.shared.loadContainer(
                from: downloader,
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration,
                progressHandler: { _ in })
        } else {
            loaded = try await LLMModelFactory.shared.loadContainer(
                from: downloader,
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration,
                progressHandler: { _ in })
        }
        container = loaded
        loadedModel = model
        log("GELADEN", extra: "modell=\(model)")
        return loaded
    }

    private func log(_ step: String, extra: String = "") {
        let report = memoryReport()
        flowMark("LOKAL \(step) \(extra) aktiv=\(report.active) frei=\(report.available) "
                 + "mlx_aktiv=\(report.mlxActive) mlx_peak=\(report.mlxPeak) mlx_cache=\(report.mlxCache) "
                 + "mlx_limit=\(Memory.memoryLimit)")
    }

    private static func configuration(for model: String) -> ModelConfiguration {
        LocalModelConfigurations.configuration(for: model)
    }

    static func localRequest(_ request: LocalChatRequest) -> LocalChatRequest {
        guard let newest = request.messages.lastIndex(where: { $0.role == .user }) else { return request }
        var trimmed = request
        trimmed.messages = request.messages.map { message in
            var copy = message
            copy.images = []
            return copy
        }
        guard request.tools.isEmpty else { return trimmed }
        var kept: [LocalMessage] = []
        if let system = trimmed.messages.first(where: { $0.role == .system }) {
            kept.append(system)
        }
        var budget = 4_000
        var recent: [LocalMessage] = []
        for message in trimmed.messages[..<newest].reversed() where message.role != .system {
            let room = message.text.count
            guard room <= budget, recent.count < 2 else { break }
            recent.insert(message, at: 0)
            budget -= room
        }
        kept.append(contentsOf: recent)
        kept.append(trimmed.messages[newest])
        let textChars = kept.reduce(0) { $0 + $1.text.count }
        if textChars <= 4_000, Self.wantsPicture(kept[kept.count - 1].text) {
            kept[kept.count - 1].images = Array(request.messages[newest].images.suffix(1))
        }
        trimmed.messages = kept
        return trimmed
    }

    private static func wantsPicture(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["bild", "foto", "photo", "picture", "image", "screenshot", "scan",
                "kamera", "camera", "diagramm", "grafik"].contains { lower.contains($0) }
    }

    private static func parameters(_ request: LocalChatRequest) -> GenerateParameters {
        var parameters = GenerateParameters(
            maxTokens: request.maxTokens ?? 700,
            temperature: request.temperature ?? (request.tools.isEmpty ? 0.7 : 0.2),
            topP: 0.95)
        parameters.prefill = PrefillParameters(
            chunking: .balanced,
            progress: { processed, total in
                guard processed == total else { return }
                flowMark("LOKAL PREFILL \(processed)/\(total) frei=\(LocalMemory.available) "
                         + "mlx_aktiv=\(Memory.activeMemory) mlx_peak=\(Memory.peakMemory) "
                         + "mlx_cache=\(Memory.cacheMemory)")
            })
        parameters.toolCallPolicy = ToolCallPolicy()
        return parameters
    }

    private static func info(_ info: GenerateCompletionInfo) -> LocalEngineInfo {
        let reason: String
        switch info.stopReason {
        case .stop: reason = "stop"
        case .length: reason = "length"
        case .cancelled: reason = "stop"
        }
        return LocalEngineInfo(promptTokens: info.promptTokenCount + info.cachedPromptTokenCount,
                               completionTokens: info.generationTokenCount,
                               finishReason: reason)
    }

    private static func message(_ message: LocalMessage) -> Chat.Message {
        let images = message.images.compactMap { CIImage(data: $0) }.map { UserInput.Image.ciImage($0) }
        switch message.role {
        case .system: return .system(message.text)
        case .user: return .user(message.text, images: images)
        case .assistant: return .assistant(message.text)
        case .tool: return .tool(message.text)
        }
    }
}

enum LocalModelConfigurations {
    static let gemmaE2BID = "mlx-community/gemma-4-e2b-it-4bit"
    static let gemmaE4BID = "mlx-community/gemma-4-e4b-it-4bit"
    static let qwen9BID = "mlx-community/Qwen3.5-9B-MLX-4bit"

    static func configuration(for model: String) -> ModelConfiguration {
        var configuration: ModelConfiguration
        switch model {
        case LocalModelConfigurations.gemmaE2BID:
            configuration = VLMRegistry.gemma4_E2B_it_4bit
            configuration.reasoningConfig = LocalEngine.reasoning
        case LocalModelConfigurations.gemmaE4BID:
            configuration = VLMRegistry.gemma4_E4B_it_4bit
            configuration.reasoningConfig = LocalEngine.reasoning
        case LocalModelConfigurations.qwen9BID:
            configuration = ModelConfiguration(id: model, defaultPrompt: "",
                                               extraEOSTokens: ["<|im_end|>"])
        default:
            configuration = ModelConfiguration(id: model, defaultPrompt: "",
                                               extraEOSTokens: [])
        }
        return configuration
    }
}

struct LocalInstalledDownloader: Downloader {
    let files: LocalModelFiles

    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        guard files.isInstalled(id) else { throw LocalEngineError.notInstalled(id) }
        return files.directory(for: id)
    }
}
