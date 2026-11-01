import GwenMobileKit
import Foundation

struct ModelTurn {
    var messages: [ChatMessage]
    var images: [Data]
    var pictureFiles: [String] = []
    var videos: [Data] = []
    var videoFiles: [String] = []
    var chatPictureCount = 0
    var carriedFileNames: [String] = []

    var needsVision: Bool { !images.isEmpty }
    var needsVideo: Bool { !videos.isEmpty }
    var pictureCount: Int { images.count }
    var picturesLeftBehind: Int { max(0, chatPictureCount - pictureCount) }

    func withoutPictures() -> ModelTurn {
        var copy = self
        copy.images = []
        copy.pictureFiles = []
        copy.videos = []
        copy.videoFiles = []
        return copy
    }

    func continuing(after answer: String, pictures: [Data], files: [String],
                    keeping limit: Int = ConversationMemory.maxPictures) -> ModelTurn {
        var copy = self
        if !answer.trimmed.isEmpty {
            copy.messages.append(ChatMessage(role: .assistant, text: answer))
        }
        copy.images += pictures
        copy.pictureFiles += files
        if let speaker = copy.messages.lastIndex(where: { $0.role == .user }), !copy.pictureFiles.isEmpty {
            copy.messages[speaker].images = copy.pictureFiles.map(Attachment.init(file:))
        }
        let surplus = copy.images.count - max(1, limit)
        if surplus > 0 {
            copy.images.removeFirst(surplus)
            copy.pictureFiles.removeFirst(min(surplus, copy.pictureFiles.count))
        }
        return copy
    }

    func positions(of files: [String]) -> [Int] {
        let wanted = Set(files)
        return pictureFiles.enumerated().filter { wanted.contains($0.element) }.map { $0.offset + 1 }
    }
}

enum ConversationMemory {
    static let maxMessages = 30
    static let maxPictures = ImagePolicy.rememberedPictures

    static func turn(from messages: [ChatMessage], load: (Attachment) -> Data?,
                     fileText: (String) -> String? = { _ in nil },
                     videoData: (String) -> Data? = { _ in nil }) -> ModelTurn {
        var loaded: [String: Data] = [:]
        var missing = Set<String>()
        func data(for picture: Attachment) -> Data? {
            if let hit = loaded[picture.file] { return hit }
            if missing.contains(picture.file) { return nil }
            guard let data = load(picture) else { missing.insert(picture.file); return nil }
            loaded[picture.file] = data
            return data
        }
        var window = Array(messages.suffix(maxMessages))
        let remembered = distinctPictures(in: window)
        var pictures: [Attachment] = []
        if let speaker = window.indices.last(where: { window[$0].role == .user }) {
            pictures = kept(remembered) { data(for: $0) != nil }
            for index in window.indices { window[index].images = [] }
            window[speaker].images = pictures
        } else {
            window = window.map(cleared)
        }
        var bytes: [Data] = []
        var files: [String] = []
        for picture in pictures {
            guard let data = data(for: picture) else { continue }
            bytes.append(data)
            files.append(picture.file)
        }
        var carried: [String] = []
        var videos: [Data] = []
        var videoFiles: [String] = []
        if let speaker = window.indices.last(where: { window[$0].role == .user }) {
            inlineFileBlocks(into: &window[speaker], fileText: fileText, carried: &carried)
        }
        for message in window.reversed() where message.role == .user {
            let file = message.files.last { $0.kind == .video }
            guard let file else { continue }
            guard let data = videoData(file.file), data.count <= VideoPolicy.maximumAttachmentBytes else {
                continue
            }
            videos = [data]
            videoFiles = [file.file]
            break
        }
        return ModelTurn(messages: window, images: bytes, pictureFiles: files,
                         videos: videos, videoFiles: videoFiles,
                         chatPictureCount: remembered.count, carriedFileNames: carried)
    }

    private static func inlineFileBlocks(into message: inout ChatMessage,
                                         fileText: (String) -> String?,
                                         carried: inout [String]) {
        let context = FileContext.build(for: message.files) { fileText($0.file) }
        guard !context.isEmpty else { return }
        carried = context.keptNames
        message.text = message.text + "\n\n" + context.text
    }

    private static func kept(_ pictures: [Attachment], usable: (Attachment) -> Bool) -> [Attachment] {
        guard let oldest = pictures.first else { return [] }
        if pictures.count <= maxPictures { return pictures.filter(usable) }
        let oldestUsable = usable(oldest)
        let room = maxPictures - (oldestUsable ? 1 : 0)
        var newest: [Attachment] = []
        for picture in pictures.reversed() {
            if newest.count == room { break }
            if picture.file == oldest.file { continue }
            guard usable(picture) else { continue }
            newest.insert(picture, at: 0)
        }
        return (oldestUsable ? [oldest] : []) + newest
    }

    private static func distinctPictures(in window: [ChatMessage]) -> [Attachment] {
        var seen = Set<String>()
        return window.flatMap(\.pictures).filter { seen.insert($0.file).inserted }
    }

    private static func cleared(_ message: ChatMessage) -> ChatMessage {
        guard !message.images.isEmpty else { return message }
        var copy = message
        copy.images = []
        return copy
    }
}
