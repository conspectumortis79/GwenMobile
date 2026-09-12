import Foundation

struct ModelTurn {
    var messages: [ChatMessage]
    var images: [Data]
    var pictureFiles: [String] = []
    var pictureNumbers: [Int] = []
    var chatPictureCount = 0

    var needsVision: Bool { !images.isEmpty }
    var pictureCount: Int { images.count }
    var picturesLeftBehind: Int { max(0, chatPictureCount - pictureCount) }

    func withoutPictures() -> ModelTurn {
        var copy = self
        copy.images = []
        copy.pictureFiles = []
        return copy
    }

    func positions(of files: [String]) -> [Int] {
        let wanted = Set(files)
        return pictureFiles.enumerated().filter { wanted.contains($0.element) }.map { $0.offset + 1 }
    }
}

enum ConversationMemory {
    static let maxMessages = 30
    static let maxPictures = ImagePolicy.maxPicturesPerRequest

    static func turn(from messages: [ChatMessage], load: (Attachment) -> Data?) -> ModelTurn {
        var window = window(from: messages)
        let remembered = distinctPictures(in: Array(messages.suffix(maxMessages)))
        var bytes: [Data] = []
        var files: [String] = []
        for index in window.indices {
            var usable: [Attachment] = []
            for attachment in window[index].images {
                guard let data = load(attachment) else { continue }
                usable.append(attachment)
                bytes.append(data)
                files.append(attachment.file)
            }
            window[index].images = usable
        }
        return ModelTurn(messages: window, images: bytes, pictureFiles: files,
                         pictureNumbers: numbers(of: files, in: remembered),
                         chatPictureCount: remembered.count)
    }

    private static func numbers(of files: [String], in all: [Attachment]) -> [Int] {
        let positions = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element.file, $0.offset + 1) })
        return files.compactMap { positions[$0] }
    }

    static func rememberedImages(from messages: [ChatMessage]) -> [Attachment] {
        window(from: messages).flatMap(\.images)
    }

    static func window(from messages: [ChatMessage]) -> [ChatMessage] {
        var window = Array(messages.suffix(maxMessages))
        guard let speaker = window.indices.last(where: { window[$0].role == .user }) else {
            return window.map(cleared)
        }
        let pictures = kept(Array(distinctPictures(in: window)))
        for index in window.indices { window[index].images = [] }
        window[speaker].images = pictures
        return window
    }

    private static func kept(_ pictures: [Attachment]) -> [Attachment] {
        guard let oldest = pictures.first, pictures.count > maxPictures else { return pictures }
        return [oldest] + Array(pictures.suffix(maxPictures - 1))
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
