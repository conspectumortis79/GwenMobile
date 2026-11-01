@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import Contacts
import EventKit
import Foundation
import MediaPlayer
import Photos
import Speech
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class PermissionLiveTests: GwenTestCase {
    private var permissionsArePreGranted: Bool {
        guard SFSpeechRecognizer.authorizationStatus() != .notDetermined else { return false }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) != .notDetermined else { return false }
        #if !targetEnvironment(macCatalyst)
        guard MPMediaLibrary.authorizationStatus() != .notDetermined else { return false }
        #endif
        guard CNContactStore.authorizationStatus(for: .contacts) != .notDetermined else { return false }
        guard EKEventStore.authorizationStatus(for: .event) != .notDetermined else { return false }
        guard EKEventStore.authorizationStatus(for: .reminder) != .notDetermined else { return false }
        return true
    }

    func testTheLivePermissionRequests() async throws {
        guard ProcessInfo.processInfo.environment["GWEN_LIVE_PERMISSIONS"] == "1" || permissionsArePreGranted else {
            throw XCTSkip("Live permission requests need pre-granted TCC entries; run scripts/grant_test_permissions.sh.")
        }
        if SFSpeechRecognizer.authorizationStatus() != .notDetermined {
            SystemSpeechRecognizer.authorizationStatusOverride = .notDetermined
            _ = try? await SystemSpeechRecognizer.authorize()
            SystemSpeechRecognizer.authorizationStatusOverride = nil
        }
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) != .notDetermined {
            _ = await SystemPhotoLibrary.authorizationDefault()
        }
        #if !targetEnvironment(macCatalyst)
        if MPMediaLibrary.authorizationStatus() != .notDetermined {
            _ = await MediaLibraryReader.requestAuthorizationDefault()
        }
        #endif
        if CNContactStore.authorizationStatus(for: .contacts) != .notDetermined {
            _ = await LiveContactDirectory.requestAccess()
        }
        if EKEventStore.authorizationStatus(for: .event) != .notDetermined {
            _ = try? await LiveCalendarEventStore.shared.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) != .notDetermined {
            _ = try? await LiveReminderEventStore.shared.requestFullAccessToReminders()
        }
        if EKEventStore.authorizationStatus(for: .event) != .notDetermined {
            CalendarService.accessStatusOverride = .notDetermined
            _ = await CalendarService.ensureAccess()
            CalendarService.accessStatusOverride = nil
        }
        if EKEventStore.authorizationStatus(for: .reminder) != .notDetermined {
            EventKitReminderStore.accessStatusOverride = .notDetermined
            _ = await EventKitReminderStore().hasAccess()
            EventKitReminderStore.accessStatusOverride = nil
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        _ = await SystemPhotoLibrary().allowsWriting()
        _ = await SystemPhotoLibrary().add(image)
        if CNContactStore.authorizationStatus(for: .contacts) != .notDetermined {
            let contactAccess = await LiveContactDirectory().access()
            XCTAssertEqual(contactAccess, .granted)
            _ = try? await LiveContactDirectory().cards()
        }
        _ = try? LiveContactCardSource(store: CNContactStore()).contactMembers(ofGroup: "unbekannt")
        _ = try? ContactCardReader.read(from: CNContactStore())
        _ = try? ContactCardReader.memberships(in: LiveContactCardSource(store: CNContactStore()))
    }
}
