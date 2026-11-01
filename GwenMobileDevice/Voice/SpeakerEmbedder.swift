@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreML
import Foundation

final class SpeakerEmbedder: @unchecked Sendable {
    static let modelName = "WeSpeakerResNet34LM_2s"
    static let windowSamples = SpeakerAudioWindows.windowSamples
    static let shared = SpeakerEmbedder()

    private static let selfTestSamples: [Float] = (0..<windowSamples).map { index in
        Float(sin(2 * Double.pi * 220 * Double(index) / 16000)) * 0.1
    }

    private let bundle: Bundle
    private let lock = NSLock()
    private let usability = LockedValue<Bool?>(nil)
    private var model: MLModel?
    private var loadFailed = false

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    #if DEBUG
    static var isBundled: Bool {
        modelURL(in: .main) != nil
    }
    #endif

    var isAvailable: Bool {
        loadedModel() != nil
    }

    var hasModel: Bool { Self.modelURL(in: bundle) != nil }

    var cachedUsability: Bool? { usability.current }

    func ensureUsable() async -> Bool {
        if let cached = cachedUsability { return cached }
        let result = await Offload.value { [self] in
            self.loadedModel() != nil && self.embed(Self.selfTestSamples) != nil
        }
        return usability.mutate { stored in
            if stored == nil { stored = result }
            return stored ?? result
        }
    }

    func preload() {
        _ = loadedModel()
    }

    func embed(_ samples: [Float]) -> [Float]? {
        guard let window = SpeakerAudioWindows.normalized(samples),
              let model = loadedModel(),
              let input = try? MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)],
                                            dataType: .float32) else { return nil }
        let pointer = input.dataPointer.assumingMemoryBound(to: Float.self)
        for index in window.indices {
            pointer[index] = window[index]
        }
        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "waveform": MLFeatureValue(multiArray: input),
        ])
        guard let provider else { return nil }
        lock.lock()
        let output = try? model.prediction(from: provider)
        lock.unlock()
        guard let array = output?.featureValue(for: "embedding")?.multiArrayValue else { return nil }
        var values = [Float](repeating: 0, count: array.count)
        if array.dataType == .float32 {
            let source = array.dataPointer.assumingMemoryBound(to: Float.self)
            for index in values.indices {
                values[index] = source[index]
            }
        } else {
            for index in values.indices {
                values[index] = array[index].floatValue
            }
        }
        return SpeakerProfileBuilder.normalized(values)
    }

    private func loadedModel() -> MLModel? {
        lock.lock()
        if let model {
            lock.unlock()
            return model
        }
        if loadFailed {
            lock.unlock()
            return nil
        }
        lock.unlock()
        guard let url = Self.modelURL(in: bundle) else {
            lock.lock()
            loadFailed = true
            lock.unlock()
            flowMark("SPRECHER modell fehlt")
            return nil
        }
        do {
            let compiled: URL
            if url.pathExtension == "mlpackage" {
                compiled = try MLModel.compileModel(at: url)
            } else {
                compiled = url
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: compiled, configuration: configuration)
            lock.lock()
            model = loaded
            lock.unlock()
            flowMark("SPRECHER modell geladen")
            return loaded
        } catch {
            lock.lock()
            loadFailed = true
            lock.unlock()
            flowMark("SPRECHER modell fehler \(TextLine.oneLine(error.localizedDescription, limit: 120))")
            return nil
        }
    }

    private static func modelURL(in bundle: Bundle) -> URL? {
        for ext in ["mlmodelc", "mlpackage"] {
            for subdirectory in [nil, "Models", "Resources/Models"] {
                if let url = bundle.url(forResource: modelName, withExtension: ext,
                                        subdirectory: subdirectory) {
                    return url
                }
            }
        }
        return nil
    }
}
