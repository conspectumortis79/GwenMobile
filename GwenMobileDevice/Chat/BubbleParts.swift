@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct BubbleStatusLine: View {
    let notice: String?
    let isLast: Bool
    let time: String?
    let isUser: Bool

    var body: some View {
        if let notice {
            Text(verbatim: notice)
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 14)
        }
        if isLast, let time {
            Text(verbatim: isUser ? "\(L.t("read")) \(time)" : time)
                .scaledFont(11)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.horizontal, 14)
        }
    }
}

struct BubbleCardArea: View {
    let isUser: Bool
    let messageID: UUID?
    let priceWatchRef: PriceWatchRef?
    let dayBriefingRef: DayBriefingRef?
    let weatherRef: WeatherRef?
    let onOpenEvent: ((CalendarRef) -> Void)?
    let onBriefingDay: ((UUID, String) -> Void)?
    let onBriefingSpeak: ((UUID) -> Void)?
    let onBriefingNotify: ((UUID) -> Void)?
    let onWeatherDay: ((UUID, String) -> Void)?
    let onWeatherSpeak: ((UUID) -> Void)?

    var body: some View {
        if !isUser, let priceWatchRef {
            PriceWatchCardView(ref: priceWatchRef)
                .padding(.top, 2)
        }
        if !isUser, let dayBriefingRef {
            let id = messageID
            DayBriefingCard(
                ref: dayBriefingRef,
                onDay: id.map { value in { day in onBriefingDay?(value, day) } },
                onSpeak: id.map { value in { onBriefingSpeak?(value) } },
                onNotify: id.map { value in { onBriefingNotify?(value) } },
                onOpenEvent: { ref in onOpenEvent?(ref) }
            )
            .padding(.top, 2)
        }
        if !isUser, let weatherRef {
            let id = messageID
            WeatherCard(
                ref: weatherRef,
                onDay: id.map { value in { date in onWeatherDay?(value, date) } },
                onSpeak: id.flatMap { value in
                    onWeatherSpeak.map { handler in { handler(value) } }
                }
            )
            .padding(.top, 2)
        }
    }
}
