@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

final class AppearanceTests: GwenTestCase {
    func testTheChoiceOffersNothingButLightAndDark() {
        XCTAssertEqual(AppAppearance.allCases, [.light, .dark])
    }

    func testLightAndDarkNameTheirScheme() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testEveryOptionSurvivesUserDefaults() {
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance(rawValue: appearance.rawValue), appearance)
        }
    }

    func testMissingOrUnknownStoredValueFallsBackToLight() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: SettingsKey.appearance)
        defaults.removeObject(forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.persisted(defaults: defaults), .light)
        defaults.set("dunkel", forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.persisted(defaults: defaults), .light)
        defaults.set("auto", forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.persisted(defaults: defaults), .light)
        defaults.set("dark", forKey: SettingsKey.appearance)
        XCTAssertEqual(AppAppearance.persisted(defaults: defaults), .dark)
        defaults.removeObject(forKey: SettingsKey.appearance)
        if let previous { defaults.set(previous, forKey: SettingsKey.appearance) }
    }

    func testEveryOptionIsLabelledInBothLanguages() {
        for language in AppLanguage.allCases {
            L.apply(language)
            for appearance in AppAppearance.allCases {
                XCTAssertFalse(appearance.label.isEmpty, "\(appearance) [\(language)] ist leer")
                XCTAssertNotEqual(appearance.label, appearance.labelKey, "\(appearance) [\(language)] fehlt")
            }
        }
    }

    func testTheTwoLabelsDiffer() {
        L.apply(.de)
        let labels = Set(AppAppearance.allCases.map(\.label))
        XCTAssertEqual(labels.count, AppAppearance.allCases.count)
    }

    func testAppearanceIsNoLegacyKeyAndSurvivesMigration() {
        XCTAssertFalse(SettingsKey.legacyKeys.contains(SettingsKey.appearance))
    }

    @MainActor func testChoosingAnOptionWritesItIntoUserDefaults() {
        let settings = AppSettings.shared
        let previous = settings.appearance
        settings.appearance = .dark
        XCTAssertEqual(UserDefaults.standard.string(forKey: SettingsKey.appearance), AppAppearance.dark.rawValue)
        settings.appearance = .light
        XCTAssertEqual(UserDefaults.standard.string(forKey: SettingsKey.appearance), AppAppearance.light.rawValue)
        settings.appearance = previous
    }

    @MainActor func testTheSingletonHandsOutTheSchemeThePickerJustChose() {
        let settings = AppSettings.shared
        let previous = settings.appearance
        settings.appearance = .dark
        XCTAssertEqual(settings.appearance.colorScheme, .dark)
        XCTAssertEqual(UserDefaults.standard.string(forKey: SettingsKey.appearance), AppAppearance.dark.rawValue)
        settings.appearance = .light
        XCTAssertEqual(settings.appearance.colorScheme, .light)
        settings.appearance = previous
    }

    func testEveryOptionNamesTheInterfaceStyleItStandsFor() {
        XCTAssertEqual(AppAppearance.light.interfaceStyle, .light)
        XCTAssertEqual(AppAppearance.dark.interfaceStyle, .dark)
    }

    func testNoOptionHandsTheStyleBackToTheSystem() {
        for appearance in AppAppearance.allCases {
            XCTAssertNotEqual(appearance.interfaceStyle, UIUserInterfaceStyle.unspecified,
                              "jede Darstellung entscheidet selbst, keine uebergibt an iOS")
        }
    }

    @MainActor func testTheSyncWritesTheStyleIntoEveryWindowItIsGiven() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let windows = [UIWindow(windowScene: scene), UIWindow(windowScene: scene), UIWindow(windowScene: scene)]
        WindowStyleSync.apply(.dark, to: windows)
        XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .dark },
                      "jedes Fenster muss den Stil bekommen, auch die zweiten Fenster")
        WindowStyleSync.apply(.light, to: windows)
        XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .light },
                      "der Wechsel ueberschreibt den Stil in jedem Fenster")
    }

    @MainActor func testTheRunningWindowAdoptsTheStyleThePickerJustChose() async throws {
        let settings = AppSettings.shared
        let previous = settings.appearance
        defer { settings.appearance = previous }

        settings.appearance = .dark
        let dark = try await styleOfTheLiveWindow(assuming: previous)
        XCTAssertEqual(dark, .dark,
                       "ohne Stil am Fenster bleibt die Mac-Titelzeile in der alten Farbe stehen")
        settings.appearance = .light
        let light = try await styleOfTheLiveWindow(assuming: .dark)
        XCTAssertEqual(light, .light)
    }

    @MainActor private func styleOfTheLiveWindow(assuming previous: AppAppearance) async throws
    -> UIUserInterfaceStyle {
        for _ in 0..<40 {
            let style = try liveWindow().overrideUserInterfaceStyle
            if style != previous.interfaceStyle { return style }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try liveWindow().overrideUserInterfaceStyle
    }

    @MainActor private func liveWindow() throws -> UIWindow {
        let windows = WindowStyleSync.sceneWindows()
        return try XCTUnwrap(windows.first { $0.isKeyWindow } ?? windows.first,
                             "im Testlauf gibt es kein Fenster des Szene-Systems")
    }
}
