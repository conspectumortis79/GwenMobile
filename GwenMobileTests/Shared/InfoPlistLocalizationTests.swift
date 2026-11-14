@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class InfoPlistLocalizationTests: XCTestCase {
    private let privacyKeys = [
        "NSAppleMusicUsageDescription",
        "NSCalendarsFullAccessUsageDescription",
        "NSCameraUsageDescription",
        "NSContactsUsageDescription",
        "NSLocalNetworkUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSSpeechRecognitionUsageDescription",
    ]

    func testEveryPermissionTheAppAsksForIsExplainedInTheBundle() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        for key in privacyKeys {
            let text = try XCTUnwrap(info[key] as? String, "\(key) fehlt in der Konfiguration")
            XCTAssertFalse(text.isEmpty, "\(key) ist leer")
            XCTAssertTrue(text.hasPrefix("GwenMobile"), "\(key) sagt nicht, wer fragt")
        }
    }

    func testEveryAppLanguageTranslatesEveryPermissionText() throws {
        for language in AppLanguage.allCases {
            let localeBundle = try XCTUnwrap(locale(for: language), "\(language.rawValue).lproj fehlt im Bundle")
            for key in privacyKeys {
                let text = localeBundle.localizedString(forKey: key, value: missing, table: "InfoPlist")
                XCTAssertNotEqual(text, missing, "\(key) ohne Text in \(language.rawValue).lproj")
                XCTAssertTrue(text.hasPrefix("GwenMobile"), "\(key) in \(language.rawValue) sagt nicht, wer fragt")
            }
        }
    }

    func testTheLanguagesActuallyDiffer() throws {
        let german = try XCTUnwrap(locale(for: .de))
        let english = try XCTUnwrap(locale(for: .en))
        let spanish = try XCTUnwrap(locale(for: .es), "es.lproj fehlt im Bundle")
        let french = try XCTUnwrap(locale(for: .fr), "fr.lproj fehlt im Bundle")
        for key in privacyKeys {
            let de = german.localizedString(forKey: key, value: missing, table: "InfoPlist")
            let en = english.localizedString(forKey: key, value: missing, table: "InfoPlist")
            let es = spanish.localizedString(forKey: key, value: missing, table: "InfoPlist")
            let fr = french.localizedString(forKey: key, value: missing, table: "InfoPlist")
            XCTAssertNotEqual(de, en, "\(key) ist in Deutsch und Englisch gleich")
            XCTAssertNotEqual(de, es, "\(key) ist in Deutsch und Spanisch gleich")
            XCTAssertNotEqual(de, fr, "\(key) ist in Deutsch und Französisch gleich")
            XCTAssertNotEqual(en, es, "\(key) ist in Englisch und Spanisch gleich")
            XCTAssertNotEqual(en, fr, "\(key) ist in Englisch und Französisch gleich")
            XCTAssertNotEqual(es, fr, "\(key) ist in Spanisch und Französisch gleich")
        }
    }

    func testTheEnglishStringsFileMirrorsTheBundleValuesExactly() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let english = try XCTUnwrap(locale(for: .en), "en.lproj fehlt im Bundle")
        for key in privacyKeys {
            let base = try XCTUnwrap(info[key] as? String, "\(key) fehlt in der Konfiguration")
            XCTAssertEqual(english.localizedString(forKey: key, value: missing, table: "InfoPlist"), base,
                           "\(key) ist in Info.plist und en.lproj nicht mehr gleich")
        }
    }

    func testTheGermanFileTranslatesEveryPrivacyKeyDifferentlyFromEnglish() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let german = try XCTUnwrap(locale(for: .de), "de.lproj fehlt im Bundle")
        for key in privacyKeys {
            let base = try XCTUnwrap(info[key] as? String, "\(key) fehlt in der Konfiguration")
            let translated = german.localizedString(forKey: key, value: missing, table: "InfoPlist")
            XCTAssertNotEqual(translated, missing, "\(key) ohne deutschen Text")
            XCTAssertNotEqual(translated, base, "\(key) ist auf Deutsch unverändert")
            XCTAssertTrue(translated.hasPrefix("GwenMobile"), "\(key) sagt auf Deutsch nicht, wer fragt")
        }
    }

    private var missing: String { "§unuebersetzt§" }

    private func locale(for language: AppLanguage) -> Bundle? {
        guard let url = Bundle.main.url(forResource: language.rawValue, withExtension: "lproj") else { return nil }
        return Bundle(url: url)
    }
}
