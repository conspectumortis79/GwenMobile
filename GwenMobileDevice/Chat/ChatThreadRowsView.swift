@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct ChatThreadRowActions {
    var onEdit: (Attachment) -> Void
    var onPreview: (ChatMessage, Attachment) -> Void
    var onDelete: (UUID) -> Void
    var onRoute: (NearbyPlace) -> Void
    var onCall: ((DialNumber) -> Void)? = nil
    var onOpenEvent: ((CalendarRef) -> Void)? = nil
    var onOpenPicture: ((ChatMessage, WebPicture) -> Void)? = nil
    var onMorePictures: ((ChatMessage) -> Void)? = nil
    var onWeatherDay: ((UUID, String) -> Void)? = nil
    var onWeatherSpeak: ((UUID) -> Void)? = nil
    var onBriefingDay: ((UUID, String) -> Void)? = nil
    var onBriefingSpeak: ((UUID) -> Void)? = nil
    var onBriefingNotify: ((UUID) -> Void)? = nil
    var onReminderOffer: ((UUID, ScanReminderOffer) -> Void)? = nil
}

struct ChatThreadRowsView: View, Equatable {
    let messages: [ChatMessage]
    let lastIsSettled: Bool
    var reviewing: Set<UUID> = []
    let media: MediaStore
    let documents: DocumentStore
    let photos: PhotoLibraryWriter
    let actions: ChatThreadRowActions

    nonisolated static func == (lhs: ChatThreadRowsView, rhs: ChatThreadRowsView) -> Bool {
        lhs.messages == rhs.messages && lhs.lastIsSettled == rhs.lastIsSettled
            && lhs.reviewing == rhs.reviewing
            && lhs.media === rhs.media && lhs.documents === rhs.documents
            && lhs.photos === rhs.photos
    }

    var body: some View {
        let rows = ChatThreadRow.grouped(messages)
        let lastID = messages.last?.id
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                switch row {
                case .day(let date):
                    ChatDayLabel(date: date).id(row.id)
                case .message(let message):
                    bubble(for: message, isLast: message.id == lastID && lastIsSettled)
                        .equatable()
                        .id(row.id)
                }
            }
        }
    }

    private func bubble(for message: ChatMessage, isLast: Bool) -> Bubble {
        var bubble = Bubble(message: message, media: media, documents: documents, photos: photos,
                            question: ChatView.question(for: message, in: messages),
                            time: ChatView.timeString(message.date),
                            isLast: isLast)
        bubble.onEdit = actions.onEdit
        bubble.onPreview = { attachment in actions.onPreview(message, attachment) }
        bubble.onDelete = actions.onDelete
        bubble.onRoute = actions.onRoute
        bubble.onCall = actions.onCall
        bubble.onOpenEvent = actions.onOpenEvent
        bubble.onOpenPicture = { picture in actions.onOpenPicture?(message, picture) }
        bubble.onMorePictures = { actions.onMorePictures?(message) }
        bubble.onWeatherDay = actions.onWeatherDay
        bubble.onWeatherSpeak = actions.onWeatherSpeak
        bubble.onBriefingDay = actions.onBriefingDay
        bubble.onBriefingSpeak = actions.onBriefingSpeak
        bubble.onBriefingNotify = actions.onBriefingNotify
        bubble.onReminderOffer = actions.onReminderOffer
        bubble.reviewPending = reviewing.contains(message.id)
        return bubble
    }
}

struct ChatDayLabel: View {
    let date: Date

    var body: some View {
        Text(verbatim: "\(Formatters.relationalDay(date)) · \(ChatView.timeString(date))")
            .scaledFont(11)
            .foregroundStyle(Color(.tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }
}
