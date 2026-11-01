import GwenMobileKit
import Foundation
import Translation

extension OnDeviceTranslation {
    #if DEBUG
    nonisolated(unsafe) static var liveSupportedCodes: @Sendable () async -> [String] = { [] }

    static func supportedCodes() async -> [String] {
        await liveSupportedCodes()
    }
    #endif

    nonisolated(unsafe) static var statusOverride: (@Sendable (TranslationJob) async -> OnDeviceStatus)?
    nonisolated(unsafe) static var liveStatus: @Sendable (TranslationJob) async -> OnDeviceStatus = { _ in
        .unsupportedPair
    }

    static func status(for job: TranslationJob) async -> OnDeviceStatus {
        if let statusOverride { return await statusOverride(job) }
        guard TranslationLanguages.withCode(job.targetCode) != nil else { return .unsupportedPair }
        return await liveStatus(job)
    }

    static func translate(_ job: TranslationJob) async throws -> String {
        guard !job.isEmpty else { throw TranslationProblem.nothingToTranslate }
        let chunks = TranslationChunks.split(job.text)
        guard !chunks.isEmpty else { throw TranslationProblem.nothingToTranslate }
        return try await perform(chunks: chunks,
                                 source: Locale.Language(identifier: sourceCode(for: job)),
                                 target: Locale.Language(identifier: job.targetCode))
    }

    nonisolated(unsafe) static var batch: @Sendable ([String], Locale.Language, Locale.Language)
        async throws -> [TranslationSession.Response] = { _, _, target in
            throw TranslationProblem.unsupportedPair(target.minimalIdentifier)
        }

    static func perform(chunks: [String], source: Locale.Language, target: Locale.Language)
        async throws -> String {
        try await Offload.run {
            do {
                let responses = try await batch(chunks, source, target)
                return stitch(chunks: chunks, responses: responses)
            } catch {
                throw problem(for: error)
            }
        }
    }
}
