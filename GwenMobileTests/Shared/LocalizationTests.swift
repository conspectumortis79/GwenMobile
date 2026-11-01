@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class LocalizationTests: GwenTestCase {
    func testEveryKeyHasEveryLanguage() {
        for (key, values) in L.strings {
            for language in AppLanguage.allCases {
                XCTAssertNotNil(values[language], "\(language.rawValue) fehlt für \(key)")
                XCTAssertFalse((values[language] ?? "").isEmpty, "\(key) [\(language.rawValue)] ist leer")
            }
        }
    }

    func testPlaceholderCountsMatchAcrossLanguages() {
        for (key, values) in L.strings {
            let de = values[.de] ?? ""
            for language in AppLanguage.allCases {
                let text = values[language] ?? ""
                XCTAssertEqual(de.countOccurrences(of: "%@"), text.countOccurrences(of: "%@"),
                               "%@ bei \(key) [\(language.rawValue)]")
                XCTAssertEqual(de.countOccurrences(of: "%d"), text.countOccurrences(of: "%d"),
                               "%d bei \(key) [\(language.rawValue)]")
            }
        }
    }

    func testWaitingLabelsLeaveTheEllipsisToTheAnimation() {
        let waitingKeys = ["processing", "asr_working", "generating_image", "editing_image",
                           "cal_working", "web_searching", "web_fetching",
                           "loading_models", "testing", "file_working", "product_reading",
                           "price_working", "call_working", "call_link_working", "music_working", "message_working",
                           "scan_reading"]
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

    func testACountOfOnePicksTheSingularText() {
        XCTAssertEqual(L.counted(1, one: "code_lines_one", many: "code_lines"), "1 line")
        XCTAssertEqual(L.counted(2, one: "code_lines_one", many: "code_lines"), "2 lines")
        XCTAssertEqual(L.counted(0, one: "code_lines_one", many: "code_lines"), "0 lines")
    }

    func testUnknownKeyIsReturnedVerbatim() {
        XCTAssertEqual(L.t("dieser_key_existiert_nicht"), "dieser_key_existiert_nicht")
    }

    func testTheTooBigNoticeNamesTheAllowedSizeInsteadOfTheFileTwice() {
        let name = "protokoll.pdf"
        let limit = StorageUsage.bytesText(FilePolicy.maxFileBytes)
        let message = L.fmt2("file_too_big", name, limit)
        XCTAssertEqual(message.components(separatedBy: name).count - 1, 1, message)
        XCTAssertTrue(message.contains(limit), "\(message) nennt \(limit) nicht")
        XCTAssertFalse(message.contains("%@"), message)
    }

    func testNoTwoSlotNoticeIsEverFilledByTheSingleSlotHelper() {
        for (key, values) in L.strings {
            let slots = AppLanguage.allCases.map { (values[$0] ?? "").components(separatedBy: "%@").count - 1 }
            XCTAssertEqual(Set(slots).count, 1, "\(key) hat unterschiedlich viele Slots pro Sprache")
            XCTAssertLessThanOrEqual(slots.max() ?? 0, 2, "\(key) braucht mehr als zwei Argumente")
        }
    }

    func testEveryStandortKeyTheSearchCanReportIsDefined() {
        for key in ["place_busy", "place_denied", "place_unavailable", "place_none_found",
                    "place_unnamed", "place_working", "place_head",
                    "route_working", "route_head", "route_not_found"] {
            guard let values = L.strings[key] else {
                XCTFail("Standort-Key fehlt: \(key)")
                continue
            }
            for language in AppLanguage.allCases {
                XCTAssertFalse((values[language] ?? "").isEmpty, "\(key) [\(language)] ist leer")
            }
        }
    }

    func testFormatHelpersSubstituteArguments() {
        XCTAssertEqual(L.fmt("cal_created", "Zahnarzt"), "✔ Appointment created: Zahnarzt")
        XCTAssertEqual(L.n("asr_countdown", 7), "Recording ends in 7 s")
    }

    func testDefaultTitleIsPartOfDefaultTitleSet() {
        for language in AppLanguage.allCases {
            L.apply(language)
            XCTAssertTrue(L.defaultTitles.contains(L.defaultTitle), "\(language.rawValue)")
        }
        L.apply(.en)
    }

    func testInvalidKeyErrorOpensSettingsAndCarriesHTTPStatus() {
        let error = L.friendlyError("some failure", status: 401)
        XCTAssertEqual(error.message, L.t("err_bad_key"))
        XCTAssertTrue(error.openSettings)
        XCTAssertTrue(error.detail.contains("HTTP 401"))
    }

    func testRateLimitMapping() {
        XCTAssertEqual(L.friendlyError("Too many requests", status: 429).message, L.t("err_rate_limited"))
        XCTAssertEqual(L.friendlyError("Throttling.AllocationQuota exceeded").message, L.t("err_rate_limited"))
    }

    func testExhaustedCreditMapsToTheCreditMessageAndOpensSettings() {
        let openRouter = L.friendlyError(#"{"error":{"message":"This request would exceed your available credits given your current in-flight requests. Retry after 10s","code":402}}"#, status: 402)
        XCTAssertEqual(openRouter.message, L.t("err_no_credit"))
        XCTAssertTrue(openRouter.openSettings)
        XCTAssertEqual(L.friendlyError("Arrearage: account balance is insufficient").message, L.t("err_no_credit"))
        XCTAssertEqual(L.friendlyError("insufficient_quota").message, L.t("err_no_credit"))
        XCTAssertEqual(L.friendlyError("each seat costs 4,429 credits").message, "each seat costs 4,429 credits")
    }

    func testDigitsInsideAnotherMessageAreNoRateLimit() {
        let tokenCount = L.friendlyError("The prompt is 14290 tokens long")
        XCTAssertEqual(tokenCount.message, "The prompt is 14290 tokens long")
        XCTAssertFalse(tokenCount.openSettings)
        let price = L.friendlyError("each seat costs 4,429 credits")
        XCTAssertEqual(price.message, "each seat costs 4,429 credits")
    }

    func testPermissionWordsOutsideAudioStayUntranslated() {
        let calendar = L.friendlyError("Permission denied for the calendar store")
        XCTAssertEqual(calendar.message, "Permission denied for the calendar store")
        let photos = L.friendlyError("no permission to write photos")
        XCTAssertEqual(photos.message, "no permission to write photos")
        XCTAssertEqual(L.friendlyError("microphone permission was refused").message, L.t("mic_denied"))
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
        L.apply(.de)
        XCTAssertEqual(L.friendlyError("rate limit hit", status: 429).message, L.strings["err_rate_limited"]?[.de])
        L.apply(.en)
        XCTAssertEqual(L.friendlyError("rate limit hit", status: 429).message, L.strings["err_rate_limited"]?[.en])
    }

    func testEveryLanguageNamesItselfForTheSwitch() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(language.id, language.rawValue)
            XCTAssertFalse(language.flag.isEmpty, language.rawValue)
            XCTAssertFalse(language.label.isEmpty, language.rawValue)
            XCTAssertFalse(language.locale.identifier.isEmpty, language.rawValue)
        }
        XCTAssertEqual(AppLanguage.allCases.map(\.label), ["Deutsch", "English", "Español", "Français"])
        XCTAssertFalse(L.defaultTitles.isEmpty)
        XCTAssertTrue(L.defaultTitles.contains(L.defaultTitle))
    }

    func testDeviceDefaultFollowsTheLocale() {
        XCTAssertEqual(AppLanguage.deviceDefault(for: Locale(identifier: "de_DE")), .de)
        XCTAssertEqual(AppLanguage.deviceDefault(for: Locale(identifier: "es_ES")), .es)
        XCTAssertEqual(AppLanguage.deviceDefault(for: Locale(identifier: "fr_FR")), .fr)
        XCTAssertEqual(AppLanguage.deviceDefault(for: Locale(identifier: "en_US")), .en)
        XCTAssertEqual(AppLanguage.deviceDefault(for: Locale(identifier: "ja_JP")), .en)
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.currencyCode.isEmpty)
        }
    }

    func testEveryLanguageHasItsOwnFormats() {
        for language in AppLanguage.allCases {
            L.apply(language)
            XCTAssertFalse(L.dayFormat.isEmpty)
            XCTAssertFalse(L.timeFormat.isEmpty)
            XCTAssertFalse(L.calStartFormat.isEmpty)
            XCTAssertFalse(L.calChipFormat.isEmpty)
        }
    }

    func testMissingKeysFallBackToTheKeyItself() {
        XCTAssertEqual(L.t("gibt_es_nicht"), "gibt_es_nicht")
        XCTAssertEqual(L.fmt("gibt_es_nicht", "x"), "gibt_es_nicht")
        XCTAssertEqual(L.fmt2("gibt_es_nicht", "a", "b"), "gibt_es_nicht")
    }

    func testDetailLineHandlesAnEmptyHeadWithAndWithoutStatus() {
        XCTAssertEqual(L.friendlyError("", status: nil).detail, "")
        XCTAssertEqual(L.friendlyError("", status: 401).detail, "HTTP 401")
    }

    func testANamelessMissingModelStillOpensTheSettings() {
        let error = L.friendlyError("model not found")
        XCTAssertTrue(error.openSettings)
        XCTAssertTrue(error.message.contains("?"), error.message)
    }
}

private extension String {
    func countOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
