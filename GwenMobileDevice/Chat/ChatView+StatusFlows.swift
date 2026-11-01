@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import Speech
import UIKit
import UserNotifications
#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
#endif

struct AppStatusReport {
    enum Level {
        case ok
        case attention
        case problem
        case neutral
    }

    struct Row {
        let label: String
        let value: String
        let level: Level
    }

    let rows: [Row]
    let summary: String
    let summaryLevel: Level

    var text: String {
        var lines = [L.t("app_status_title")]
        for row in rows {
            lines.append("\(Self.symbol(row.level)) \(row.label): \(row.value)")
        }
        lines.append("")
        lines.append("\(Self.symbol(summaryLevel)) \(summary)")
        lines.append(L.t("app_status_footer_local"))
        return lines.joined(separator: "\n")
    }

    static func symbol(_ level: Level) -> String {
        switch level {
        case .ok: return "✅"
        case .attention: return "⚠️"
        case .problem: return "⛔️"
        case .neutral: return "ℹ️"
        }
    }
}

@MainActor
struct AppStatusReader {
    let store: ChatStore
    let settings: AppSettings

    func read() async -> AppStatusReport {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let notificationsAllowed = Self.notificationsAllowed(notificationSettings.authorizationStatus)
        let briefingPending = pending.filter {
            $0.identifier.hasPrefix(DayBriefingNotifier.identifier)
        }.count
        var rows: [AppStatusReport.Row] = []
        rows.append(appRow())
        rows.append(contentsOf: providerRows())
        rows.append(contentsOf: permissionRows(notificationStatus: notificationSettings.authorizationStatus))
        rows.append(await speakerRow())
        rows.append(await storageRow())
        rows.append(await watchRow())
        rows.append(briefingRow(notificationsAllowed: notificationsAllowed, pending: briefingPending))
        rows.append(backgroundRow())
        rows.append(row(L.t("app_status_label_network"), L.t("app_status_value_not_checked"), .neutral))
        let problems = rows.filter { $0.level == .problem }.count
        let hints = rows.filter { $0.level == .attention }.count
        if problems > 0 {
            return AppStatusReport(rows: rows,
                                   summary: L.counted(problems, one: "app_status_summary_problem_one",
                                                      many: "app_status_summary_problem"),
                                   summaryLevel: .problem)
        }
        if hints > 0 {
            return AppStatusReport(rows: rows,
                                   summary: L.counted(hints, one: "app_status_summary_attention_one",
                                                      many: "app_status_summary_attention"),
                                   summaryLevel: .attention)
        }
        return AppStatusReport(rows: rows,
                               summary: L.t("app_status_summary_ok"),
                               summaryLevel: .ok)
    }

    private func appRow() -> AppStatusReport.Row {
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        return row(L.t("app_status_label_app"),
                   "\(AppInfo.installed.versionLine) · \(system)",
                   .ok)
    }

    private func providerRows() -> [AppStatusReport.Row] {
        let descriptor = settings.provider.descriptor
        let configured = settings.isConfigured
        let providerValue = configured
            ? descriptor.title
            : descriptor.title + " · " + L.t("app_status_value_not_configured")
        var rows = [row(L.t("app_status_label_provider"), providerValue, configured ? .ok : .problem)]
        let model = settings.chatModel.trimmed
        if model.isEmpty {
            rows.append(row(L.t("app_status_label_model"), L.t("app_status_value_missing"), .problem))
        } else {
            let value = settings.profile.needsListing
                ? model + " · " + L.t("app_status_value_not_checked")
                : model
            rows.append(row(L.t("app_status_label_model"), value,
                            settings.profile.needsListing ? .attention : .ok))
        }
        rows.append(Self.keyRow(blocked: settings.vault.hasBlockedEntry || settings.keychainProblem != nil,
                                present: !settings.key(for: settings.provider).isEmpty,
                                optional: descriptor.keyIsOptional(settings.connections)))
        return rows
    }

    static func keyRow(blocked: Bool, present: Bool, optional: Bool) -> AppStatusReport.Row {
        let label = L.t("api_key")
        if blocked { return AppStatusReport.Row(label: label, value: L.t("app_status_value_blocked"), level: .problem) }
        if present { return AppStatusReport.Row(label: label, value: L.t("app_status_value_present"), level: .ok) }
        if optional { return AppStatusReport.Row(label: label, value: L.t("app_status_value_optional"), level: .ok) }
        return AppStatusReport.Row(label: label, value: L.t("app_status_value_missing"), level: .problem)
    }

    static func notificationRow(_ status: UNAuthorizationStatus) -> AppStatusReport.Row {
        let label = L.t("app_status_label_notifications")
        if notificationsAllowed(status) {
            return AppStatusReport.Row(label: label, value: L.t("app_status_value_allowed"), level: .ok)
        }
        let key = status == .notDetermined ? "app_status_value_not_determined" : "app_status_value_denied"
        return AppStatusReport.Row(label: label, value: L.t(key), level: .attention)
    }

    private func permissionRows(notificationStatus: UNAuthorizationStatus) -> [AppStatusReport.Row] {
        [
            microphoneRow(),
            speechRow(),
            Self.notificationRow(notificationStatus),
            calendarRow(),
            reminderRow(),
            contactRow(),
            locationRow(),
            photoRow(),
            alarmRow(),
        ]
    }

    private enum AccessState {
        case allowed
        case limited
        case denied
        case notDetermined
        case unavailable
    }

    private func accessRow(_ labelKey: String, _ state: AccessState,
                           limitedLevel: AppStatusReport.Level = .ok) -> AppStatusReport.Row {
        switch state {
        case .allowed:
            return row(L.t(labelKey), L.t("app_status_value_allowed"), .ok)
        case .limited:
            return row(L.t(labelKey), L.t("app_status_value_limited"), limitedLevel)
        case .denied:
            return row(L.t(labelKey), L.t("app_status_value_denied"), .attention)
        case .notDetermined:
            return row(L.t(labelKey), L.t("app_status_value_not_determined"), .attention)
        case .unavailable:
            return row(L.t(labelKey), L.t("app_status_value_unavailable"), .attention)
        }
    }

    private func microphoneRow() -> AppStatusReport.Row {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return accessRow("app_status_label_microphone", .allowed)
        case .denied:
            return accessRow("app_status_label_microphone", .denied)
        case .undetermined:
            return accessRow("app_status_label_microphone", .notDetermined)
        @unknown default:
            return accessRow("app_status_label_microphone", .unavailable)
        }
    }

    private func speechRow() -> AppStatusReport.Row {
        let authorization = SFSpeechRecognizer.authorizationStatus()
        var available = SFSpeechRecognizer(locale: L.lang.locale)?.isAvailable ?? false
        if SpeechTranscriber.isAvailable {
            available = true
        }
        switch authorization {
        case .authorized:
            return row(L.t("app_status_label_speech"),
                       L.t(available ? "app_status_value_allowed" : "app_status_value_unavailable"),
                       available ? .ok : .attention)
        case .denied, .restricted:
            return accessRow("app_status_label_speech", .denied)
        case .notDetermined:
            return accessRow("app_status_label_speech", .notDetermined)
        @unknown default:
            return accessRow("app_status_label_speech", .unavailable)
        }
    }

    private func calendarRow() -> AppStatusReport.Row {
        eventKitRow("app_status_label_calendar", CalendarService.accessStatus)
    }

    private func reminderRow() -> AppStatusReport.Row {
        eventKitRow("app_status_label_reminders", EventKitReminderStore.accessStatus)
    }

    private func eventKitRow(_ labelKey: String, _ status: EKAuthorizationStatus) -> AppStatusReport.Row {
        accessRow(labelKey, Self.accessState(status), limitedLevel: .attention)
    }

    private func contactRow() -> AppStatusReport.Row {
        accessRow("app_status_label_contacts", Self.accessState(LiveContactDirectory.authorizationStatus()))
    }

    private func locationRow() -> AppStatusReport.Row {
        accessRow("app_status_label_location", Self.accessState(CLLocationManager().authorizationStatus))
    }

    private func photoRow() -> AppStatusReport.Row {
        accessRow("app_status_label_photos", Self.accessState(PHPhotoLibrary.authorizationStatus(for: .addOnly)))
    }

    private func alarmRow() -> AppStatusReport.Row {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        switch AlarmKitTimer.authorizationState() {
        case .authorized:
            return accessRow("app_status_label_alarms", .allowed)
        case .denied:
            return accessRow("app_status_label_alarms", .denied)
        case .notDetermined:
            return accessRow("app_status_label_alarms", .notDetermined)
        @unknown default:
            return accessRow("app_status_label_alarms", .unavailable)
        }
        #else
        return row(L.t("app_status_label_alarms"), L.t("app_status_value_unavailable"), .neutral)
        #endif
    }

    private static func accessState(_ status: EKAuthorizationStatus) -> AccessState {
        switch status {
        case .fullAccess: return .allowed
        case .writeOnly: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private static func accessState(_ status: CNAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .allowed
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private static func accessState(_ status: CLAuthorizationStatus) -> AccessState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .allowed
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private static func accessState(_ status: PHAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .allowed
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private func speakerRow() async -> AppStatusReport.Row {
        guard settings.voice.onlyMyVoice else {
            return row(L.t("speaker_profile"), L.t("state_off"), .neutral)
        }
        guard let profile = SpeakerProfileStore.shared.load() else {
            return row(L.t("speaker_profile"), L.t("speaker_profile_missing"), .problem)
        }
        let usable = await SpeakerEmbedder.shared.ensureUsable()
        let detail = usable ? L.t("app_status_value_available") : L.t("app_status_value_unavailable")
        return row(L.t("speaker_profile"),
                   L.counted(profile.sampleCount, one: "speaker_profile_ready_one", many: "speaker_profile_ready")
                       + " · " + detail,
                   usable ? .ok : .problem)
    }

    private func storageRow() async -> AppStatusReport.Row {
        await store.cleaner.refreshUsage()
        let usage = store.cleaner.usage
        if let problem = store.storageProblem {
            return row(L.t("storage"), problem, .problem)
        }
        guard FileManager.default.isWritableFile(atPath: store.media.paths.support.path) else {
            return row(L.t("storage"), L.t("app_status_value_not_writable"), .problem)
        }
        let value = StorageUsage.joined([usage.historyLine, usage.imagesLine, usage.documentsLine])
        return row(L.t("storage"), value, .ok)
    }

    private func watchRow() async -> AppStatusReport.Row {
        let total = await store.watches.count()
        guard total > 0 else {
            return row(L.t("price_watch_card_head"), L.t("app_status_value_none"), .neutral)
        }
        let active = await store.watches.active().count
        let due = await store.watches.due().count
        let value = L.n("app_status_value_watches", active)
            + (due > 0 ? " · " + L.n("app_status_value_due", due) : "")
        return row(L.t("price_watch_card_head"), value, due > 0 ? .attention : .ok)
    }

    private func briefingRow(notificationsAllowed: Bool, pending: Int) -> AppStatusReport.Row {
        guard settings.briefing.enabled else {
            return row(L.t("brief_settings"), L.t("state_off"), .neutral)
        }
        guard notificationsAllowed else {
            return row(L.t("brief_settings"),
                       L.t("state_on") + " · " + L.t("app_status_value_denied"), .attention)
        }
        guard pending > 0 else {
            return row(L.t("brief_settings"),
                       L.t("state_on") + " · " + L.t("app_status_value_none"), .attention)
        }
        return row(L.t("brief_settings"),
                   L.t("state_on") + " · " + L.n("app_status_value_scheduled", pending), .ok)
    }

    private func backgroundRow() -> AppStatusReport.Row {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return accessRow("app_status_label_background", .allowed)
        case .denied:
            return accessRow("app_status_label_background", .denied)
        case .restricted:
            return accessRow("app_status_label_background", .limited, limitedLevel: .attention)
        @unknown default:
            return accessRow("app_status_label_background", .unavailable)
        }
    }

    private func row(_ label: String, _ value: String,
                     _ level: AppStatusReport.Level) -> AppStatusReport.Row {
        AppStatusReport.Row(label: label, value: value, level: level)
    }

    static func notificationsAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }
}

extension ChatView {
    @MainActor func runAppStatusFlow(convID: UUID, started: Date, slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let report = await withBusy(L.t("app_status_working")) {
            await AppStatusReader(store: store, settings: settings).read()
        }
        guard !Task.isCancelled else { return }
        flowMarkPersonal("STATUS geprüft zeilen=\(report.rows.count)")
        finishAnswer(report.text, model: settings.chatModel, convID: convID, started: started, slot: slot)
    }
}
