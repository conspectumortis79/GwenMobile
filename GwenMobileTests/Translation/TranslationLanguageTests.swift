@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TranslationLanguageTests: GwenTestCase {
    func testEveryCodeAppearsOnlyOnce() {
        let codes = TranslationLanguages.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "\(codes)")
    }

    func testTheCatalogueNamesEveryCodeInBothAppLanguages() {
        for language in AppLanguage.allCases {
            for entry in TranslationLanguages.all {
                let name = entry.name(for: language)
                XCTAssertFalse(name.isEmpty, "\(entry.code) [\(language)]")
                XCTAssertNotEqual(name, entry.code, "\(entry.code) [\(language)] bleibt der Rohcode")
            }
        }
    }

    func testWithCodeAcceptsWhatTheFrameworkReportsBack() {
        XCTAssertEqual(TranslationLanguages.withCode("de-Latn-DE")?.code, "de")
        XCTAssertEqual(TranslationLanguages.withCode("zh-Hans-CN")?.code, "zh-Hans")
        XCTAssertEqual(TranslationLanguages.withCode("EN")?.code, "en")
        XCTAssertEqual(TranslationLanguages.withCode("sr-Latn-RS")?.code, "sr")
        XCTAssertNil(TranslationLanguages.withCode("xx-YY"))
        XCTAssertNil(TranslationLanguages.withCode(""))
    }

    func testPairLabelNamesBothLanguagesInAppLanguage() {
        L.apply(.de)
        XCTAssertEqual(TranslationLanguages.pairLabel(from: "de", to: "fr"), "Deutsch → Französisch")
        L.apply(.en)
        XCTAssertEqual(TranslationLanguages.pairLabel(from: "de", to: "fr"), "German → French")
        XCTAssertTrue(TranslationLanguages.pairLabel(from: nil, to: "fr").contains("French"))
    }
}

final class TranslationCopyTests: XCTestCase {
    private let keys = L10nTable.values.keys
        .filter { $0.hasPrefix("translate_") || $0 == "translating" }
        .sorted()

    func testEveryKeyCarriesEveryLanguage() {
        XCTAssertEqual(keys.count, 8)
        for key in keys {
            let values = L10nTable.values[key] ?? [:]
            let de = values[.de] ?? ""
            for language in AppLanguage.allCases {
                let text = values[language] ?? ""
                XCTAssertFalse(text.isEmpty, "\(key) [\(language.rawValue)]")
                XCTAssertEqual(de.components(separatedBy: "%@").count, text.components(separatedBy: "%@").count,
                               "%@ bei \(key) [\(language.rawValue)]")
            }
        }
    }

    func testTheWaitingLabelLeavesTheEllipsisToTheAnimation() {
        for language in AppLanguage.allCases {
            L.apply(language)
            let text = L.fmt("translating", "Deutsch → Französisch")
            XCTAssertFalse(text.hasSuffix("…") || text.hasSuffix("..."), text)
            XCTAssertTrue(text.contains("Deutsch → Französisch"), text)
        }
    }

    func testProblemCopyNeverLeaksTheKey() {
        L.apply(.de)
        for problem in [TranslationProblem.nothingToTranslate, .packMissing("fr"),
                        .unsupportedPair("nl"), .device("Grund"), .model("Grund")] {
            XCTAssertFalse(problem.copy.isEmpty)
            XCTAssertFalse(problem.copy.hasPrefix("translate_"), problem.copy)
        }
        XCTAssertTrue(TranslationProblem.packMissing("fr").opensSettings)
        XCTAssertFalse(TranslationProblem.nothingToTranslate.opensSettings)
        XCTAssertEqual(TranslationProblem.device("Grund").detail, "Grund")
    }
}

final class TranslationVocabularyTests: GwenTestCase {
    func testTheLanguageIdentityAndTheFallbackTarget() {
        let language = TranslationLanguages.withCode("fr") ?? TranslationLanguage(code: "fr")
        XCTAssertEqual(language.id, language.code)
        L.apply(.de)
        XCTAssertEqual(TranslationLanguages.fallbackTarget, "en")
        L.apply(.en)
        XCTAssertEqual(TranslationLanguages.fallbackTarget, "de")
        L.apply(.es)
        XCTAssertEqual(TranslationLanguages.fallbackTarget, "en")
    }

    func testUnknownCodesStillProduceUsableNames() {
        XCTAssertEqual(TranslationLanguage(code: "").name(for: .de), "")
        let unknown = TranslationLanguage(code: "xx")
        XCTAssertEqual(unknown.name(for: .de), "xx")
        let script = TranslationLanguage(code: "de-Qaaa")
        XCTAssertTrue(script.name(for: .de).contains("Qaaa"), script.name(for: .de))
        XCTAssertEqual(TranslationLanguages.named("gibt_es_nicht"), "gibt_es_nicht")
    }
}
