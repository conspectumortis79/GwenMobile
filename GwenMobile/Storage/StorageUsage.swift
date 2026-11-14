import GwenMobileKit
import Foundation

struct StorageUsage: Equatable, Sendable {
    var conversations: Int = 0
    var messages: Int = 0
    var imageFiles: Int = 0
    var imageBytes: Int = 0
    var documentFiles: Int = 0
    var documentBytes: Int = 0
    var exportFiles: Int = 0
    var exportBytes: Int = 0
    var bytesByConversation: [UUID: Int] = [:]

    var imageBytesText: String { StorageUsage.bytesText(imageBytes) }

    var documentBytesText: String { StorageUsage.bytesText(documentBytes) }
    var exportBytesText: String { StorageUsage.bytesText(exportBytes) }

    #if DEBUG
    var attachmentsBytes: Int { StorageUsage.sum([imageBytes, documentBytes]) }

    var summaryText: String {
        StorageUsage.joined([String(imageFiles + documentFiles), StorageUsage.bytesText(attachmentsBytes)])
    }
    #endif

    var imagesLine: String {
        "\(StorageUsage.counted(imageFiles, "images_word")) (\(imageBytesText))"
    }

    var documentsLine: String {
        "\(StorageUsage.counted(documentFiles, "files_word")) (\(documentBytesText))"
    }

    var exportsLine: String {
        guard exportFiles > 0 else { return "" }
        return "\(StorageUsage.counted(exportFiles, "exports_word")) (\(exportBytesText))"
    }

    var historyLine: String {
        StorageUsage.joined([StorageUsage.counted(conversations, "conversations_word"),
                             StorageUsage.counted(messages, "messages_word")])
    }

    var headerLine: String {
        StorageUsage.joined([StorageUsage.counted(conversations, "conversations_word"),
                             imageBytesText, documentBytes > 0 ? documentBytesText : ""])
    }

    var deleteAllBody: String {
        L.fmt2("delete_all_body", String(conversations),
               StorageUsage.joined([imagesLine]
                                   + (documentFiles > 0 ? [documentsLine] : [])
                                   + (exportsLine.isEmpty ? [] : [exportsLine])))
    }

    static func counted(_ amount: Int, _ wordKey: String) -> String {
        "\(amount) \(L.t(wordKey))"
    }

    static func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func bytesText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func sum<Values: Sequence>(_ values: Values) -> Int where Values.Element == Int {
        values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            return overflow ? Int.max : result
        }
    }
}

protocol FileInventory: Sendable {
    func fileNames() -> [String]
    func byteSize(of file: String) -> Int
}

protocol StorageInventory: Sendable {
    func countedFiles() -> Int
    func countedBytes() -> Int
}

extension FileInventory {
    func sizesByName() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: fileNames().map { ($0, byteSize(of: $0)) })
    }
}

extension MediaStore: FileInventory {}
extension DocumentStore: FileInventory {}

enum StorageMeasurement {
    static func usage(conversations: [Conversation], images: FileInventory,
                      documents: FileInventory? = nil,
                      exports: (any StorageInventory)? = nil) -> StorageUsage {
        var usage = StorageUsage()
        usage.conversations = conversations.count
        usage.messages = conversations.reduce(0) { $0 + $1.messages.count }
        let sizes = images.sizesByName()
        let documentSizes = documents?.sizesByName() ?? [:]
        usage.imageFiles = sizes.count
        usage.imageBytes = StorageUsage.sum(sizes.values)
        usage.documentFiles = documentSizes.count
        usage.documentBytes = StorageUsage.sum(documentSizes.values)
        usage.exportFiles = exports?.countedFiles() ?? 0
        usage.exportBytes = exports?.countedBytes() ?? 0
        var combined = sizes
        for (name, size) in documentSizes { combined[name] = size }
        for conversation in conversations {
            usage.bytesByConversation[conversation.id] = referencedBytes(of: conversation, sizes: combined)
        }
        return usage
    }

    private static func referencedBytes(of conversation: Conversation, sizes: [String: Int]) -> Int {
        let images = Set(conversation.messages.flatMap(\.storedImageFiles))
        let documents = Set(conversation.messages.flatMap(\.documentFiles))
        return StorageUsage.sum([
            StorageUsage.sum(images.map { sizes[$0] ?? 0 }),
            StorageUsage.sum(documents.map { sizes[$0] ?? 0 }),
        ])
    }
}
