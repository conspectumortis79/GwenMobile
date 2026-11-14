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

    let source: ChatMessage?
    let text: String
    let isUser: Bool
    let question: String?
    var streaming: Bool
    let images: [Attachment]
    let outImages: [Attachment]
    let model: String?
    let elapsed: Double?
    let time: String?
    let isLast: Bool
    var onEdit: ((Attachment) -> Void)? = nil
    var onPreview: ((Attachment) -> Void)? = nil
    var onRoute: ((NearbyPlace) -> Void)? = nil
    var onCall: ((DialNumber) -> Void)? = nil
    let messageID: UUID?
    var onDelete: ((UUID) -> Void)? = nil
    let sources: [WebSource]
    let sourcesHeadingKey: String?
    let sourceReview: SourceReview?
    let sourceReport: WebSourceReport?
    var reviewPending: Bool = false
    let gallery: PictureGallery?
    var onOpenPicture: ((WebPicture) -> Void)? = nil
    var onMorePictures: (() -> Void)? = nil
    let placeGroups: [PlaceGroup]
    var onOpenEvent: ((CalendarRef) -> Void)? = nil
    let calendarRef: CalendarRef?
    let reminderRef: ReminderRef?
    let reminderOffer: ScanReminderOffer?
    let scanRef: AttachedFile?
    var onReminderOffer: ((UUID, ScanReminderOffer) -> Void)? = nil
    let thinking: ThinkingLevel?
    let files: [AttachedFile]
    let ocrFiles: [OcrFile]
    let fileRefs: [FileRef]
    let fileRefsHeadingKey: String?
    let memoryRefs: [MemoryRef]
    let weatherRef: WeatherRef?
    let priceWatchRef: PriceWatchRef?
    let dayBriefingRef: DayBriefingRef?
    var onBriefingDay: ((UUID, String) -> Void)? = nil
    var onBriefingSpeak: ((UUID) -> Void)? = nil
    var onBriefingNotify: ((UUID) -> Void)? = nil
    var onOpenSourceReport: ((WebSourceReport) -> Void)? = nil
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
        self.source = message
        self.text = message.text
        self.isUser = message.role == .user
        self.question = question
        self.streaming = false
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
        self.sourceReport = message.sourceReport
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
        self.source = nil
        self.text = text
        self.isUser = isUser
        self.question = question
        self.streaming = streaming
        self.images = []
        self.outImages = []
        self.model = nil
        self.elapsed = nil
        self.time = nil
        self.isLast = false
        self.media = nil
        self.documents = nil
        self.photos = Self.implicitPhotos
        self.messageID = nil
        self.sources = []
        self.sourcesHeadingKey = nil
        self.sourceReview = nil
        self.sourceReport = nil
        self.gallery = nil
        self.placeGroups = []
        self.calendarRef = nil
        self.reminderRef = nil
        self.reminderOffer = nil
        self.scanRef = nil
        self.thinking = nil
        self.files = []
        self.ocrFiles = []
        self.fileRefs = []
        self.fileRefsHeadingKey = nil
        self.memoryRefs = []
        self.weatherRef = nil
        self.priceWatchRef = nil
        self.dayBriefingRef = nil
    }

    nonisolated static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.source == rhs.source
            && lhs.text == rhs.text && lhs.isUser == rhs.isUser && lhs.streaming == rhs.streaming
            && lhs.question == rhs.question && lhs.time == rhs.time && lhs.isLast == rhs.isLast
            && lhs.reviewPending == rhs.reviewPending
            && lhs.messageID == rhs.messageID
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
