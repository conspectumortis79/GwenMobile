@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class VoiceCatalogTests: GwenTestCase {
    func testLabelsKeepTheSystemNameAndAddOnlyAForeignRegion() {
        let home = VoiceOption(id: "a", name: "Anna (Premium)", language: "de-DE")
        XCTAssertEqual(home.label(defaultLanguage: "de-DE"), "Anna (Premium)")
        let foreign = VoiceOption(id: "d", name: "Daniel", language: "en-GB")
        let label = foreign.label(defaultLanguage: "en-US")
        XCTAssertTrue(label.hasPrefix("Daniel ("), label)
        XCTAssertTrue(label.contains(VoiceOption.regionName(of: "en-GB") ?? "?"), label)
    }

    func testBaseNameDropsTheQualitySuffixOnly() {
        L.apply(.de)
        XCTAssertEqual(VoiceOption.baseName("Anna (Premium)"), "Anna")
        XCTAssertEqual(VoiceOption.baseName("Anna (Erweitert)"), "Anna")
        XCTAssertEqual(VoiceOption.baseName("Anna"), "Anna")
        XCTAssertEqual(VoiceOption.baseName("(Test)"), "(Test)")
        XCTAssertTrue(VoiceCatalog.defaultLabel(for: .de).hasPrefix("Standard: "))
        L.apply(.en)
        XCTAssertTrue(VoiceCatalog.defaultLabel(for: .en).hasPrefix("Default: "))
        L.apply(.es)
        XCTAssertTrue(VoiceCatalog.defaultLabel(for: .es).hasPrefix("Predeterminada: "))
        L.apply(.fr)
        XCTAssertTrue(VoiceCatalog.defaultLabel(for: .fr).hasPrefix("Par défaut : "))
        L.apply(.en)
    }

    func testSortingPutsTheHomeLanguageFirstThenRegionThenName() {
        let options = [
            VoiceOption(id: "1", name: "Zoe", language: "en-GB"),
            VoiceOption(id: "2", name: "samantha", language: "en-US"),
            VoiceOption(id: "3", name: "Aaron", language: "en-US"),
            VoiceOption(id: "4", name: "Karen", language: "en-AU"),
        ]
        XCTAssertEqual(VoiceCatalog.sorted(options, defaultLanguage: "en-US").map(\.id), ["3", "2", "4", "1"])
    }

    func testPersonalVoicesRemainAvailableWhenTheyUseAnotherLanguage() {
        let personal = VoiceOption(id: "personal", name: "Alex", language: "en-US", isPersonal: true)
        let german = VoiceOption(id: "german", name: "Anna", language: "de-DE")
        let english = VoiceOption(id: "english", name: "Daniel", language: "en-GB")
        let options = VoiceCatalog.options(for: .de, from: [german, personal, english])
        XCTAssertEqual(options.map(\.id), ["personal", "german"])
    }

    func testPersonalVoicesSortBeforeSystemVoicesAndKeepTheirOwnLabel() {
        L.apply(.en)
        let personal = VoiceOption(id: "personal", name: "Alex", language: "en-US", isPersonal: true)
        let system = VoiceOption(id: "system", name: "Aaron", language: "en-US")
        let sorted = VoiceCatalog.sorted([system, personal], defaultLanguage: "en-US")
        XCTAssertEqual(sorted.map(\.id), ["personal", "system"])
        XCTAssertEqual(personal.label(defaultLanguage: "en-US"), L.fmt("voice_personal_label", "Alex"))
        XCTAssertTrue(system.label(defaultLanguage: "en-GB").hasPrefix("Aaron ("))
    }

    func testUnknownVoiceIdentifierIsNotTreatedAsPersonal() {
        XCTAssertFalse(VoiceCatalog.isPersonalVoice(identifier: ""))
        XCTAssertFalse(VoiceCatalog.isPersonalVoice(identifier: "com.example.missing"))
    }

    func testOptionsFilterToTheAppLanguageAndTheDefaultVoiceIsReadable() {
        let german = VoiceCatalog.options(for: .de)
        XCTAssertTrue(german.allSatisfy { $0.isPersonal || $0.language.hasPrefix("de") })
        let english = VoiceCatalog.options(for: .en)
        XCTAssertTrue(english.allSatisfy { $0.isPersonal || $0.language.hasPrefix("en") })
        let spanish = VoiceCatalog.options(for: .es)
        XCTAssertTrue(spanish.allSatisfy { $0.isPersonal || $0.language.hasPrefix("es") })
        let french = VoiceCatalog.options(for: .fr)
        XCTAssertTrue(french.allSatisfy { $0.isPersonal || $0.language.hasPrefix("fr") })
        XCTAssertFalse(VoiceCatalog.defaultVoiceName(for: .de).isEmpty)
        XCTAssertFalse(VoiceCatalog.defaultVoiceName(for: .en).isEmpty)
        XCTAssertFalse(VoiceCatalog.defaultVoiceName(for: .es).isEmpty)
        XCTAssertFalse(VoiceCatalog.defaultVoiceName(for: .fr).isEmpty)
        XCTAssertEqual(VoiceCatalog.defaultLanguage(for: .de), "de-DE")
        XCTAssertEqual(VoiceCatalog.defaultLanguage(for: .en), "en-US")
        XCTAssertEqual(VoiceCatalog.defaultLanguage(for: .es), "es-ES")
        XCTAssertEqual(VoiceCatalog.defaultLanguage(for: .fr), "fr-FR")
    }

    func testUnknownIdentifierFallsBackToTheDefaultVoice() {
        let fallback = VoiceCatalog.voice(identifier: "com.example.nope", language: .en)
        XCTAssertEqual(fallback?.identifier, VoiceCatalog.defaultVoice(for: .en)?.identifier)
        XCTAssertEqual(VoiceCatalog.voice(identifier: VoiceOption.systemDefaultID, language: .de)?.identifier,
                       VoiceCatalog.defaultVoice(for: .de)?.identifier)
    }
}
