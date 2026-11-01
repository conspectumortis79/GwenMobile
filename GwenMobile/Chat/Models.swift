import GwenMobileKit
import Foundation

enum Role: String, Codable {
    case user
    case assistant
}

struct Attachment: Codable, Hashable {
    var file: String

    enum CodingKeys: String, CodingKey {
        case file
    }
}

extension Attachment {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        file = fields.content(String.self, .file, fallback: "")
    }
}

struct WebSource: Codable, Hashable {
    var title: String
    var url: String
    var domain: String

    enum CodingKeys: String, CodingKey {
        case title, url, domain
    }
}

extension WebSource {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        title = fields.content(String.self, .title, fallback: "")
        url = fields.content(String.self, .url, fallback: "")
        domain = fields.content(String.self, .domain, fallback: "")
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: Role
    var text: String
    var images: [Attachment] = []
    var date: Date = Date()
    var model: String? = nil
    var elapsed: Double? = nil
    var outImages: [Attachment]? = nil
    var sources: [WebSource]? = nil
    var sourcesHeadingKey: String? = nil
    var sourceReview: SourceReview? = nil
    var thinking: ThinkingLevel? = nil
    var placeGroups: [PlaceGroup]? = nil
    var files: [AttachedFile] = []
    var ocrFiles: [OcrFile]? = nil
    var fileRefs: [FileRef]? = nil
    var fileRefsHeadingKey: String? = nil
    var gallery: PictureGallery? = nil
    var calendarRef: CalendarRef? = nil
    var reminderRef: ReminderRef? = nil
    var reminderOffer: ScanReminderOffer? = nil
    var scanRef: AttachedFile? = nil
    var memoryRefs: [MemoryRef]? = nil
    var weatherRef: WeatherRef? = nil
    var priceWatchRef: PriceWatchRef? = nil
    var dayBriefingRef: DayBriefingRef? = nil

    enum CodingKeys: String, CodingKey {
        case id, role, text, images, date, model, elapsed, outImages, sources, sourcesHeadingKey, thinking,
             sourceReview,
             placeGroups, files, ocrFiles, fileRefs, fileRefsHeadingKey, gallery, calendarRef, reminderRef,
             reminderOffer, scanRef, memoryRefs, weatherRef, priceWatchRef, dayBriefingRef
    }

    enum LegacyPlaceKeys: String, CodingKey {
        case places, placesHeadingKey
    }
}

extension ChatMessage {
    mutating func applyAnswer(from fresh: ChatMessage) {
        text = fresh.text
        model = fresh.model
        elapsed = fresh.elapsed
        outImages = fresh.outImages
        files = fresh.files
        sources = fresh.sources
        sourcesHeadingKey = fresh.sourcesHeadingKey
        sourceReview = fresh.sourceReview
        thinking = fresh.thinking
        placeGroups = fresh.placeGroups
        fileRefs = fresh.fileRefs
        fileRefsHeadingKey = fresh.fileRefsHeadingKey
        gallery = fresh.gallery
        calendarRef = fresh.calendarRef
        reminderRef = fresh.reminderRef
        memoryRefs = fresh.memoryRefs
        weatherRef = fresh.weatherRef
        priceWatchRef = fresh.priceWatchRef
        dayBriefingRef = fresh.dayBriefingRef
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.metadata(UUID.self, .id, fallback: UUID())
        role = fields.metadata(Role.self, .role, fallback: .assistant)
        text = fields.content(String.self, .text, fallback: "")
        images = Self.named(fields.content([Attachment].self, .images, fallback: []))
        date = fields.metadata(Date.self, .date, fallback: Date())
        model = fields.metadata(String.self, .model)
        elapsed = fields.metadata(Double.self, .elapsed)
        outImages = fields.content([Attachment].self, .outImages).map(Self.named)
        sources = fields.content([WebSource].self, .sources)
        sourcesHeadingKey = fields.metadata(String.self, .sourcesHeadingKey)
        sourceReview = fields.content(SourceReview.self, .sourceReview)
        thinking = fields.metadata(ThinkingLevel.self, .thinking)
        placeGroups = try fields.content([PlaceGroup].self, .placeGroups) ?? Self.legacyPlaceGroups(decoder)
        files = fields.content([AttachedFile].self, .files, fallback: []).filter { !$0.file.isEmpty }
        ocrFiles = fields.content([OcrFile].self, .ocrFiles)
        fileRefs = fields.content([FileRef].self, .fileRefs)
        fileRefsHeadingKey = fields.metadata(String.self, .fileRefsHeadingKey)
        gallery = fields.content(PictureGallery.self, .gallery)
            .flatMap { $0.pictures.isEmpty ? nil : $0 }
        calendarRef = fields.content(CalendarRef.self, .calendarRef)
            .flatMap { $0.isOpenable ? $0 : nil }
        reminderRef = fields.content(ReminderRef.self, .reminderRef)
            .flatMap { $0.isOpenable ? $0 : nil }
        reminderOffer = fields.content(ScanReminderOffer.self, .reminderOffer)
            .flatMap { $0.isUsable ? $0 : nil }
        scanRef = fields.content(AttachedFile.self, .scanRef)
            .flatMap { $0.file.isEmpty ? nil : $0 }
        memoryRefs = fields.content([MemoryRef].self, .memoryRefs)
        weatherRef = fields.content(WeatherRef.self, .weatherRef).flatMap { $0.isOpenable ? $0 : nil }
        priceWatchRef = fields.content(PriceWatchRef.self, .priceWatchRef)
            .flatMap { $0.isUsable ? $0 : nil }
        dayBriefingRef = fields.content(DayBriefingRef.self, .dayBriefingRef)
            .flatMap { $0.isUsable ? $0 : nil }
    }

    private static func legacyPlaceGroups(_ decoder: Decoder) throws -> [PlaceGroup]? {
        let legacy = try LenientFields<LegacyPlaceKeys>(decoder)
        return PlaceGroup.single(legacy.content([NearbyPlace].self, .places) ?? [],
                                 headingKey: legacy.metadata(String.self, .placesHeadingKey))
    }

    private static func named(_ attachments: [Attachment]) -> [Attachment] {
        attachments.filter { !$0.file.isEmpty }
    }
}

extension ChatMessage {
    var pictures: [Attachment] { images + (outImages ?? []) }
    var imageFiles: [String] { pictures.map(\.file) }
    var galleryFiles: [String] { gallery?.files ?? [] }
    var storedImageFiles: [String] { imageFiles + galleryFiles }
    #if DEBUG
    var hasGallery: Bool { gallery.map { !$0.pictures.isEmpty } ?? false }
    var allPlaces: [NearbyPlace] { placeGroups?.flatMap(\.places) ?? [] }
    #endif
    var documentFiles: [String] {
        var out = files.map(\.file).filter { !$0.isEmpty }
        if let scanRef, !scanRef.file.isEmpty, !out.contains(scanRef.file) { out.append(scanRef.file) }
        return out
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, title, messages, updatedAt
    }
}

extension Conversation {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.metadata(UUID.self, .id, fallback: UUID())
        title = fields.content(String.self, .title, fallback: L.defaultTitle)
        messages = fields.content([ChatMessage].self, .messages, fallback: [])
        updatedAt = fields.metadata(Date.self, .updatedAt, fallback: Date())
    }
}

final class DecodeIssues: Sendable {
    static let userInfoKey = CodingUserInfoKey(rawValue: "gwenmobileDecodeIssues")

    private let fields = LockedValue([String]())

    var isDamaged: Bool { !fields.current.isEmpty }

    var damagedFields: String { fields.current.joined(separator: ",") }

    func noteDamaged(_ field: String) {
        fields.mutate { stored in
            if !stored.contains(field) { stored.append(field) }
        }
    }
}

extension Decoder {
    var decodeIssues: DecodeIssues? {
        DecodeIssues.userInfoKey.flatMap { userInfo[$0] as? DecodeIssues }
    }
}
