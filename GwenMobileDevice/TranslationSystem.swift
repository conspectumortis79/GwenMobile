@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation
import Translation

enum TranslationSystem {
    @MainActor static func install() {
        #if DEBUG
        OnDeviceTranslation.liveSupportedCodes = {
            await LanguageAvailability().supportedLanguages.map {
                $0.languageCode?.identifier ?? "?"
            }
        }
        #endif
        OnDeviceTranslation.liveStatus = { job in
            let availability = LanguageAvailability()
            let source = Locale.Language(identifier: OnDeviceTranslation.sourceCode(for: job))
            let target = Locale.Language(identifier: job.targetCode)
            let state = await availability.status(from: source, to: target)
            if state == .installed { return .ready }
            if state == .supported { return .packMissing }
            return .unsupportedPair
        }
        OnDeviceTranslation.batch = { chunks, source, target in
            let session = TranslationSession(installedSource: source, target: target)
            let requests = chunks.enumerated().map { pair in
                TranslationSession.Request(sourceText: pair.element, clientIdentifier: "\(pair.offset)")
            }
            return try await session.translations(from: requests)
        }
    }
}
