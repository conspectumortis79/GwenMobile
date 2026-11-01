@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct DayBriefingCard: View, Equatable {
    let ref: DayBriefingRef
    var onDay: ((String) -> Void)? = nil
    var onSpeak: (() -> Void)? = nil
    var onNotify: (() -> Void)? = nil
    var onOpenEvent: ((CalendarRef) -> Void)? = nil

    nonisolated static func == (lhs: DayBriefingCard, rhs: DayBriefingCard) -> Bool {
        lhs.ref == rhs.ref
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            dayPicker
            if !ref.events.isEmpty {
                block(L.t("brief_head_events")) {
                    ForEach(ref.events) { event in
                        eventRow(event)
                    }
                }
            } else {
                block(L.t("brief_head_events")) {
                    Text(L.t("brief_no_events"))
                        .scaledFont(13)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            if let travel = ref.travel, travel.hasTimes {
                block(L.t("brief_head_travel")) {
                    row(symbol: "car.fill", tint: Color(.systemBlue), title: travel.title,
                        detail: DayBriefingAnswers.travelText(travel))
                }
            }
            if !ref.reminders.isEmpty {
                block(L.t("brief_head_open")) {
                    ForEach(ref.reminders) { item in
                        row(symbol: item.overdue ? "exclamationmark.circle.fill" : "checklist",
                            tint: item.overdue ? Color(.systemRed) : Color(.systemOrange),
                            title: item.title, detail: item.detail, badge: item.badge)
                    }
                }
            }
            if !ref.birthdays.isEmpty {
                block(L.t("brief_head_birthday")) {
                    ForEach(ref.birthdays) { item in
                        row(symbol: "gift.fill", tint: Color(.systemPink),
                            title: item.title, detail: item.detail)
                    }
                }
            }
            actions
        }
        .cardChrome()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.greeting)
                    .scaledFont(17, weight: .bold)
                Text(ref.dayText)
                    .scaledFont(12.5)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 6)
            if let weather = ref.weather, let line = weatherLine(weather) {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: weatherSymbol(weather))
                            .scaledFont(18)
                            .symbolRenderingMode(.multicolor)
                        Text(line.range)
                            .scaledFont(13, weight: .semibold)
                    }
                    if !line.note.isEmpty {
                        Text(line.note)
                            .scaledFont(11)
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var dayPicker: some View {
        DayTabPicker(
            tabs: BriefingDay.allCases.map { DayTabPicker.Tab(id: $0.rawValue, title: $0.title) },
            selected: ref.selectedDay?.rawValue ?? "",
            onSelect: { onDay?($0) })
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(Color(.secondaryLabel))
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func eventRow(_ event: DayBriefingEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            icon("calendar", tint: Color(.systemIndigo))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title)
                    .scaledFont(13.5, weight: .semibold)
                    .lineLimit(2)
                Text(verbatim: DayBriefingAnswers.eventDetail(event))
                    .scaledFont(12)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if let ref = event.ref {
                Button(action: TapProbe.action({
                    onOpenEvent?(ref)
                })) {
                    Text(L.t("brief_open_event"))
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Color(.systemIndigo))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("brief_open_event"))
            }
        }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String,
                     badge: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            icon(symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .scaledFont(13.5, weight: .semibold)
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .scaledFont(12)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let badge, !badge.isEmpty {
                Text(verbatim: badge)
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(tint)
            }
        }
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(Circle().fill(tint.opacity(0.14)))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: TapProbe.action({
                onSpeak?()
            })) {
                Label(L.t("brief_speak"), systemImage: "speaker.wave.2.fill")
                    .scaledFont(12.5, weight: .semibold)
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 4)
            Button(action: TapProbe.action({
                onNotify?()
            })) {
                Label(L.t("brief_notify"), systemImage: "bell.badge.fill")
                    .scaledFont(12.5, weight: .semibold)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Color(.systemOrange))
    }

    private func weatherLine(_ weather: WeatherRef) -> (range: String, note: String)? {
        WeatherAdviceRules.rangeAndNote(for: weather)
    }

    private func weatherSymbol(_ weather: WeatherRef) -> String {
        if let advice = WeatherAdviceRules.advice(for: weather).first { return advice.symbol }
        guard !weather.hours.isEmpty else { return WeatherKind.cloud.symbol }
        return weather.hours[weather.hours.count / 2].kind.symbol
    }
}
