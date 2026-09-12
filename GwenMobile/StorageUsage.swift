import Foundation

struct StorageUsage: Equatable, Sendable {
    var conversations: Int = 0
    var messages: Int = 0
    var imageFiles: Int = 0
    var imageBytes: Int = 0
    var bytesByConversation: [UUID: Int] = [:]

    var imageBytesText: String {
        ByteCountFormatter.string(fromByteCount: Int64(imageBytes), countStyle: .file)
    }

    var summaryText: String {
        "\(imageFiles) · \(imageBytesText)"
    }

    var imagesLine: String {
        "\(imageFiles) \(L.t("images_word")) (\(imageBytesText))"
    }

    static func bytesText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

protocol ImageInventoryReading: Sendable {
    func imageFileNames() -> [String]
    func byteSize(of file: String) -> Int
}

extension MediaStore: ImageInventoryReading {}

enum StorageMeasurement {
    static func usage(conversations: [Conversation], inventory: ImageInventoryReading) -> StorageUsage {
        var usage = StorageUsage()
        usage.conversations = conversations.count
        usage.messages = conversations.reduce(0) { $0 + $1.messages.count }
        var sizes: [String: Int] = [:]
        for name in inventory.imageFileNames() {
            sizes[name] = inventory.byteSize(of: name)
        }
        usage.imageFiles = sizes.count
        usage.imageBytes = sizes.values.reduce(0) { $0 + $1 }
        for conversation in conversations {
            usage.bytesByConversation[conversation.id] = referencedBytes(of: conversation, sizes: sizes)
        }
        return usage
    }

    private static func referencedBytes(of conversation: Conversation, sizes: [String: Int]) -> Int {
        conversation.messages.reduce(0) { total, message in
            total + message.images.reduce(0) { $0 + (sizes[$1.file] ?? 0) }
                + (message.outImages ?? []).reduce(0) { $0 + (sizes[$1.file] ?? 0) }
        }
    }
}
