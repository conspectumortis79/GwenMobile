import GwenMobileKit
import Foundation

enum SendRoute: Equatable {
    case imageEdit
    case imageCreate
    case videoCreate(VideoRequest)
    case pictureSearch(query: String)
    case translate(TranslationJob)
    case scanDocument(ScanRequest)
    case calendar
    case reminder(ReminderRequest)
    case timer(TimerRequest)
    case readAloud(ReadAloudRequest)
    case readAnswer
    case code(language: CodeLanguage)
    case nearbyPlace(terms: [String], mode: TravelMode)
    case routeToPlace(terms: [String], mode: TravelMode)
    case priceSearch(terms: [String], country: String?, nearby: Bool)
    case priceWatch(PriceWatchRequest)
    case dayBriefing(DayBriefingRequest)
    case call(ContactRequest)
    case clock(ClockRequest)
    case music(MusicRequest)
    case message(MessageRequest)
    case memory(MemoryRequest)
    case history
    case weather(WeatherRequest)
    case appStatus
    case chat
}

struct SendContext: Equatable {
    var attachedImage = false
    var rememberedImage = false
    var attachedVideo = false
    var attachedFile = false
    var scannedDocument = false
    var documentReminder = false
    var textNeedsTheModel: Bool { attachedImage || attachedVideo || attachedFile || scannedDocument }
}

struct RoutedSend {
    let text: String
    let plan: SendPlan
    let turn: ModelTurn
    let history: [ChatMessage]
    let attachments: [Attachment]
    let files: [AttachedFile]
    var convID: UUID
    let started: Date
    var freshPictureFiles: [String] = []

    var attachedPictures: [Data] {
        let files = Set(attachments.map(\.file))
        return zip(turn.pictureFiles, turn.images).filter { files.contains($0.0) }.map(\.1)
    }

    @MainActor func continuing(with carry: AnswerCarry, since index: Int,
                               media: MediaStore) async -> RoutedSend {
        let note = carry.text(since: index)
        let known = Set(turn.pictureFiles)
        var wanted: [Attachment] = []
        var seen = Set<String>()
        func add(_ picture: Attachment) {
            guard !picture.file.isEmpty, !known.contains(picture.file),
                  seen.insert(picture.file).inserted else { return }
            wanted.append(picture)
        }
        for piece in carry.freshPieces(since: index) {
            for picture in piece.artifacts.outImages ?? [] { add(picture) }
            for picture in (piece.artifacts.gallery?.pictures ?? []).prefix(ImagePolicy.galleryChainPictures) {
                add(picture.attachment)
            }
        }
        guard !note.isEmpty || !wanted.isEmpty else { return self }
        let pictures = wanted
        let loaded = await Offload.value { () -> [(file: String, data: Data)] in
            pictures.compactMap { picture in media.data(for: picture).map { (picture.file, $0) } }
        }
        var older = history
        if !note.isEmpty { older.append(ChatMessage(role: .assistant, text: note)) }
        return RoutedSend(text: text,
                          plan: plan,
                          turn: turn.continuing(after: note, pictures: loaded.map(\.data),
                                                files: loaded.map(\.file)),
                          history: older,
                          attachments: attachments, files: files,
                          convID: convID, started: started,
                          freshPictureFiles: loaded.isEmpty ? freshPictureFiles : loaded.map(\.file))
    }
}
