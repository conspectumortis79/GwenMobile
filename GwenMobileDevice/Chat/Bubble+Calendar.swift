@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    @MainActor func calendarView(_ ref: CalendarRef) -> some View {
        chipSection(headKey: "cal_chip_head", openAppKey: "cal_open_in_app",
                    symbol: "calendar", colour: Color(.systemGreen),
                    title: ref.chipTitle, stamp: ref.chipStamp,
                    open: { openAppointment(ref) }, openApp: { openCalendarApp() })
    }

    @MainActor func reminderView(_ ref: ReminderRef) -> some View {
        chipSection(headKey: "rem_chip_head", openAppKey: "rem_open_in_app",
                    symbol: "checklist", colour: Color(.systemOrange),
                    title: ref.chipTitle, stamp: ref.chipStamp,
                    open: { openReminder(ref) }, openApp: { openRemindersApp() })
    }

    @MainActor private func chipSection(headKey: String, openAppKey: String,
                                        symbol: String, colour: Color,
                                        title: String, stamp: String,
                                        open: @escaping () -> Void,
                                        openApp: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t(headKey))
            CapsuleAction(horizontal: 9, vertical: 6, action: open) {
                chipBody(symbol: symbol, colour: colour, title: title, stamp: stamp)
            }
            .accessibilityLabel(L.t(headKey))
            .contextMenu {
                Button(action: open) {
                    Label(L.t(headKey), systemImage: symbol)
                }
                Button(action: openApp) {
                    Label(L.t(openAppKey), systemImage: "arrow.up.forward.app")
                }
            }
        }
    }

    @MainActor func chipBody(symbol: String, colour: Color, title: String,
                                     stamp: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .scaledFont(15)
                .foregroundStyle(colour)
            Text(verbatim: title)
                .scaledFont(12, weight: .semibold)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(verbatim: stamp)
                .scaledFont(11)
                .foregroundStyle(Color(.secondaryLabel))
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .bold)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    @MainActor func openReminder(_ ref: ReminderRef) {
        let outcome = ReminderChip.outcome(for: ref, hasAccess: EventKitReminderStore.hasAccess,
                                          isLive: EventKitReminderStore.isLive(_:))
        guard case .present = outcome else {
            if let key = ReminderChip.noticeKey(for: outcome) { notice.show(L.t(key)) }
            return
        }
        openRemindersApp()
    }

    @MainActor func openRemindersApp(at index: Int = 0) {
        let urls = ReminderChip.remindersURLs
        guard index < urls.count else {
            notice.show(L.t("rem_open_in_app_failed"))
            return
        }
        UIApplication.shared.open(urls[index]) { opened in
            guard !opened else { return }
            Task { @MainActor in openRemindersApp(at: index + 1) }
        }
    }

    @MainActor func reminderOfferView(_ offer: ScanReminderOffer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t("scan_reminder_head"))
            Button(action: TapProbe.action({
                guard let messageID else { return }
                onReminderOffer?(messageID, offer)
            })) {
                HStack(spacing: 9) {
                    Image(systemName: "bell.badge.fill")
                        .scaledFont(15)
                        .foregroundStyle(Color(.systemOrange))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: offer.title)
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let stamp = offer.chipStamp {
                            Text(verbatim: stamp)
                                .scaledFont(11)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    Spacer(minLength: 8)
                    Text(L.t("scan_reminder_action"))
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Color(.systemOrange))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 268, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.systemOrange).opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("scan_reminder_action"))
        }
    }

    @MainActor func openAppointment(_ ref: CalendarRef) {
        let outcome = CalendarChip.outcome(for: ref, hasAccess: CalendarService.hasAccess,
                                          isLive: CalendarService.isLive(_:))
        guard case .present(let live) = outcome else {
            if let key = CalendarChip.noticeKey(for: outcome) { notice.show(L.t(key)) }
            return
        }
        onOpenEvent?(live)
    }

    @MainActor func openCalendarApp() {
        guard let url = CalendarChip.todayURL else { return }
        UIApplication.shared.open(url) { opened in
            guard !opened else { return }
            Task { @MainActor in notice.show(L.t("cal_open_in_app_failed")) }
        }
    }

}
