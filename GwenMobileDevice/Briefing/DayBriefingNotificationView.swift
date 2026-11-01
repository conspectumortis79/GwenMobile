@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct DayBriefingNotificationView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject var desk = DayBriefingDesk()
    @StateObject var speech = SpeechSynthesizer()
    @State var ref: DayBriefingRef?
    @State var targetDay: BriefingDay
    @State var loadGeneration = 0
    @State var calendarEvent: CalendarRef?

    init(day: BriefingDay) {
        _targetDay = State(initialValue: day)
        flowMark("BRIEFING detail init tag=\(day.rawValue)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let ref {
                    DayBriefingCard(ref: ref,
                                    onDay: { raw in switchDay(raw) },
                                    onSpeak: { speak(ref) },
                                    onNotify: { notify(ref) },
                                    onOpenEvent: { calendarEvent = $0 })
                        .padding(16)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("brief_working"))
                            .scaledFont(13)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L.t("brief_notify_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done"), action: TapProbe.action({ dismiss() }))
                }
            }
            .task { if ref == nil { await load(targetDay) } }
            .sheet(item: $calendarEvent) { event in
                CalendarEventView(ref: event) { calendarEvent = nil }
            }
        }
        .windowAppearance()
    }

    private func switchDay(_ raw: String) {
        guard let day = BriefingDay(rawValue: raw), day != targetDay else { return }
        Task { await load(day) }
    }

    private func load(_ day: BriefingDay) async {
        loadGeneration += 1
        let generation = loadGeneration
        targetDay = day
        ref = nil
        flowMark("BRIEFING detail laden tag=\(day.rawValue)")
        let service = desk.service(includes: settings.briefing.includes)
        let fresh = await service.build(day)
        guard generation == loadGeneration else { return }
        ref = fresh
        flowMark("BRIEFING detail fertig tag=\(day.rawValue) termine=\(fresh.events.count) "
                 + "offen=\(fresh.reminders.count)")
    }

    private func speak(_ ref: DayBriefingRef) {
        speech.speak(text: DayBriefingAnswers.text(ref), voiceIdentifier: settings.voice.outputVoice)
    }

    private func notify(_ ref: DayBriefingRef) {
        DayBriefingNotifier.preparePermission()
        DayBriefingNotifier.post(ref)
    }
}
