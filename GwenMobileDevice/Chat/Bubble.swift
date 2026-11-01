@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

struct Bubble: View, Equatable {
    final class AttrBox {
        let value: AttributedString
        init(_ v: AttributedString) { value = v }
    }

    static let mdCache: NSCache<NSString, AttrBox> = {
        let c = NSCache<NSString, AttrBox>()
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    let text: String
    let isUser: Bool
    var question: String? = nil
    var streaming: Bool = false
    var images: [Attachment] = []
    var outImages: [Attachment] = []
    var model: String? = nil
    var elapsed: Double? = nil
    var time: String? = nil
    var isLast: Bool = false
    var onEdit: ((Attachment) -> Void)? = nil
    var onPreview: ((Attachment) -> Void)? = nil
    var onRoute: ((NearbyPlace) -> Void)? = nil
    var onCall: ((DialNumber) -> Void)? = nil
    var messageID: UUID?
    var onDelete: ((UUID) -> Void)? = nil
    var sources: [WebSource] = []
    var sourcesHeadingKey: String? = nil
    var sourceReview: SourceReview? = nil
    var reviewPending: Bool = false
    var gallery: PictureGallery? = nil
    var onOpenPicture: ((WebPicture) -> Void)? = nil
    var onMorePictures: (() -> Void)? = nil
    var placeGroups: [PlaceGroup] = []
    var onOpenEvent: ((CalendarRef) -> Void)? = nil
    var calendarRef: CalendarRef? = nil
    var reminderRef: ReminderRef? = nil
    var reminderOffer: ScanReminderOffer? = nil
    var scanRef: AttachedFile? = nil
    var onReminderOffer: ((UUID, ScanReminderOffer) -> Void)? = nil
    var thinking: ThinkingLevel? = nil
    var files: [AttachedFile] = []
    var ocrFiles: [OcrFile] = []
    var fileRefs: [FileRef] = []
    var fileRefsHeadingKey: String? = nil
    var memoryRefs: [MemoryRef] = []
    var weatherRef: WeatherRef? = nil
    var priceWatchRef: PriceWatchRef? = nil
    var dayBriefingRef: DayBriefingRef? = nil
    var onBriefingDay: ((UUID, String) -> Void)? = nil
    var onBriefingSpeak: ((UUID) -> Void)? = nil
    var onBriefingNotify: ((UUID) -> Void)? = nil
    var onWeatherDay: ((UUID, String) -> Void)? = nil
    var onWeatherSpeak: ((UUID) -> Void)? = nil
    let media: MediaStore?
    let documents: DocumentStore?
    let photos: PhotoLibraryWriter
    @MainActor static let implicitPhotos = PhotoLibraryWriter()
    @StateObject var notice = NoticeLine()
    @State var shareFailure: String?
    @State var claimNote: SourceReview.ClaimResult?

    init(message: ChatMessage, media: MediaStore, documents: DocumentStore? = nil,
         photos: PhotoLibraryWriter,
         question: String? = nil, time: String? = nil,
         isLast: Bool = false,
         onEdit: ((Attachment) -> Void)? = nil,
         onPreview: ((Attachment) -> Void)? = nil,
         onRoute: ((NearbyPlace) -> Void)? = nil,
         onDelete: ((UUID) -> Void)? = nil) {
        self.text = message.text
        self.isUser = message.role == .user
        self.question = question
        self.images = message.images
        self.outImages = message.outImages ?? []
        self.model = message.model
        self.elapsed = message.elapsed
        self.time = time
        self.isLast = isLast
        self.onEdit = onEdit
        self.onPreview = onPreview
        self.onRoute = onRoute
        self.messageID = message.id
        self.onDelete = onDelete
        self.sources = message.sources ?? []
        self.sourcesHeadingKey = message.sourcesHeadingKey
        self.sourceReview = message.sourceReview
        self.gallery = message.gallery
        self.placeGroups = message.placeGroups ?? []
        self.calendarRef = message.calendarRef
        self.reminderRef = message.reminderRef
        self.reminderOffer = message.reminderOffer
        self.scanRef = message.scanRef
        self.thinking = message.thinking
        self.files = message.files
        self.ocrFiles = message.ocrFiles ?? []
        self.fileRefs = message.fileRefs ?? []
        self.fileRefsHeadingKey = message.fileRefsHeadingKey
        self.memoryRefs = message.memoryRefs ?? []
        self.weatherRef = message.weatherRef
        self.priceWatchRef = message.priceWatchRef
        self.dayBriefingRef = message.dayBriefingRef
        self.media = media
        self.documents = documents
        self.photos = photos
    }

    init(text: String, isUser: Bool, question: String? = nil, streaming: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.question = question
        self.streaming = streaming
        self.media = nil
        self.documents = nil
        self.photos = Self.implicitPhotos
        self.messageID = nil
    }

    nonisolated static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.text == rhs.text && lhs.isUser == rhs.isUser && lhs.streaming == rhs.streaming
            && lhs.question == rhs.question
            && lhs.images == rhs.images && lhs.outImages == rhs.outImages
            && lhs.model == rhs.model && lhs.elapsed == rhs.elapsed && lhs.time == rhs.time
            && lhs.isLast == rhs.isLast && lhs.sources == rhs.sources
            && lhs.sourcesHeadingKey == rhs.sourcesHeadingKey
            && lhs.sourceReview == rhs.sourceReview
            && lhs.reviewPending == rhs.reviewPending
            && lhs.gallery == rhs.gallery
            && lhs.thinking == rhs.thinking
            && lhs.messageID == rhs.messageID
            && lhs.placeGroups == rhs.placeGroups
            && lhs.calendarRef == rhs.calendarRef
            && lhs.reminderRef == rhs.reminderRef
            && lhs.reminderOffer == rhs.reminderOffer
            && lhs.scanRef == rhs.scanRef
            && lhs.files == rhs.files
            && lhs.ocrFiles == rhs.ocrFiles
            && lhs.fileRefs == rhs.fileRefs
            && lhs.fileRefsHeadingKey == rhs.fileRefsHeadingKey
            && lhs.memoryRefs == rhs.memoryRefs
            && lhs.weatherRef == rhs.weatherRef
            && lhs.priceWatchRef == rhs.priceWatchRef
            && lhs.dayBriefingRef == rhs.dayBriefingRef
            && lhs.media === rhs.media
            && lhs.documents === rhs.documents
            && lhs.photos === rhs.photos
    }

    var body: some View {
        #if DEBUG
        let _ = RenderStats.bubbleBody.bump()
        #endif
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            messageContent
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .alert(claimNote.map(Self.claimAlertTitle) ?? "", isPresented: Binding(
                    get: { claimNote != nil },
                    set: { if !$0 { claimNote = nil } }
                )) {
                    Button(L.t("ok"), role: .cancel, action: TapProbe.action({ claimNote = nil }))
                } message: {
                    Text(verbatim: claimNote.map(Self.claimAlertMessage) ?? "")
                }
            BubbleStatusLine(notice: notice.text, isLast: isLast, time: time, isUser: isUser)
        }
        .contextMenu { bubbleContextMenu }
        .alert(L.t("error"), isPresented: Binding(
            get: { shareFailure != nil },
            set: { if !$0 { shareFailure = nil } }
        )) {
            Button(L.t("ok"), role: .cancel, action: TapProbe.action({ shareFailure = nil }))
        } message: {
            Text(verbatim: shareFailure ?? "")
        }
    }

    nonisolated static func claimAlertTitle(_ result: SourceReview.ClaimResult) -> String {
        result.verdict == .contradicted ? L.t("source_inline_contradicted") : L.t("source_inline_unsupported")
    }

    nonisolated static func claimAlertMessage(_ result: SourceReview.ClaimResult) -> String {
        [result.claim, SourceClaimListView.detail(result)].compactMap { $0 }.joined(separator: "\n\n")
    }
}

struct CapsuleAction<Content: View>: View {
    private let insets: EdgeInsets
    private let action: () -> Void
    private let content: Content

    init(horizontal: CGFloat, vertical: CGFloat, action: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(insets: EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal),
                  action: action, content: content)
    }

    init(insets: EdgeInsets, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.insets = insets
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(insets)
                .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
    }
}
