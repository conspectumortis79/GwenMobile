import XCTest
@testable import GwenMobile

final class LocalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testEveryKeyHasBothLanguages() {
        for (key, values) in L.strings {
            XCTAssertNotNil(values[.de], "de fehlt für \(key)")
            XCTAssertNotNil(values[.en], "en fehlt für \(key)")
        }
    }

    func testPlaceholderCountsMatchAcrossLanguages() {
        for (key, values) in L.strings {
            let de = values[.de] ?? ""
            let en = values[.en] ?? ""
            XCTAssertEqual(de.countOccurrences(of: "%@"), en.countOccurrences(of: "%@"), "%@ bei \(key)")
            XCTAssertEqual(de.countOccurrences(of: "%d"), en.countOccurrences(of: "%d"), "%d bei \(key)")
        }
    }

    func testWaitingLabelsLeaveTheEllipsisToTheAnimation() {
        let waitingKeys = ["processing", "asr_working", "generating_image", "editing_image",
                           "cal_working", "making_chart", "web_searching", "web_fetching",
                           "loading_models", "testing"]
        for key in waitingKeys {
            guard let values = L.strings[key] else {
                XCTFail("Warteschleifen-Key fehlt: \(key)")
                continue
            }
            for language in AppLanguage.allCases {
                let text = values[language] ?? ""
                XCTAssertFalse(text.hasSuffix("…") || text.hasSuffix("..."), "\(key) [\(language)] trägt eine eigene Ellipse")
                XCTAssertFalse(text.isEmpty, "\(key) [\(language)] ist leer")
            }
        }
    }

    func testUnknownKeyIsReturnedVerbatim() {
        XCTAssertEqual(L.t("dieser_key_existiert_nicht"), "dieser_key_existiert_nicht")
    }

    func testFormatHelpersSubstituteArguments() {
        XCTAssertEqual(L.fmt("cal_created", "Zahnarzt"), "✔ Termin angelegt: Zahnarzt")
        XCTAssertEqual(L.n("asr_countdown", 7), "Aufnahme endet in 7 s")
    }

    func testDefaultTitleIsPartOfDefaultTitleSet() {
        L.apply(.de)
        XCTAssertTrue(L.defaultTitles.contains(L.defaultTitle))
        L.apply(.en)
        XCTAssertTrue(L.defaultTitles.contains(L.defaultTitle))
    }

    func testInvalidKeyErrorOpensSettingsAndCarriesHTTPStatus() {
        let error = L.friendlyError("some failure", status: 401)
        XCTAssertEqual(error.message, L.t("err_bad_key"))
        XCTAssertTrue(error.openSettings)
        XCTAssertTrue(error.detail.contains("HTTP 401"))
    }

    func testRateLimitMapping() {
        XCTAssertEqual(L.friendlyError("Too many requests", status: 429).message, L.t("err_rate_limited"))
    }

    func testMissingModelNamesTheModel() {
        let error = L.friendlyError("Model not found", model: "qwen3.8-max")
        XCTAssertTrue(error.message.contains("qwen3.8-max"))
        XCTAssertTrue(error.openSettings)
    }

    func testTLSResetIsReportedAsABlockedSearchEngine() {
        XCTAssertEqual(L.friendlyError("A TLS error caused the secure connection to fail.").message,
                       L.t("net_tls_blocked"))
        XCTAssertTrue(L.friendlyError("A TLS error caused the secure connection to fail.").detail
                      .contains("TLS error"))
        XCTAssertFalse(L.friendlyError("A TLS error caused the secure connection to fail.").openSettings)
    }

    func testMicrophoneAndNetworkAndRecordingLengthMappings() {
        XCTAssertEqual(L.friendlyError("AVAudioSession is not authorized to record audio.").message, L.t("mic_denied"))
        XCTAssertEqual(L.friendlyError("not connected to the internet").message, L.t("net_error"))
        XCTAssertEqual(L.friendlyError("Input exceeded maximum duration").message, L.t("asr_too_long"))
    }

    func testUnknownErrorPassesThroughWithoutDetail() {
        let error = L.friendlyError("völlig unbekannt")
        XCTAssertEqual(error.message, "völlig unbekannt")
        XCTAssertEqual(error.detail, "")
        XCTAssertFalse(error.openSettings)
    }

    func testDetailLineIsCappedAtSixtyCharacters() {
        let error = L.friendlyError(String(repeating: "x", count: 200), status: 429)
        XCTAssertTrue(error.detail.hasPrefix(String(repeating: "x", count: 60) + "…"))
    }

    func testPersistedLanguageIsReadWithoutAppSettings() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: SettingsKey.language)
        defaults.set("en", forKey: SettingsKey.language)
        XCTAssertEqual(L.persistedLanguage(), .en)
        defaults.set("de", forKey: SettingsKey.language)
        XCTAssertEqual(L.persistedLanguage(), .de)
        defaults.removeObject(forKey: SettingsKey.language)
        XCTAssertEqual(L.persistedLanguage(), AppLanguage.deviceDefault)
        if let previous { defaults.set(previous, forKey: SettingsKey.language) }
    }

    func testLanguageSwitchChangesMessages() {
        XCTAssertEqual(L.friendlyError("rate limit hit", status: 429).message, L.strings["err_rate_limited"]?[.de])
        L.apply(.en)
        XCTAssertEqual(L.friendlyError("rate limit hit", status: 429).message, L.strings["err_rate_limited"]?[.en])
    }
}

private extension String {
    func countOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
