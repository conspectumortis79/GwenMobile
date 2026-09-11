import Foundation

struct StoragePaths: Sendable {
    let documents: URL

    init(documents: URL? = nil, fileManager: FileManager = .default) {
        self.documents = documents ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var images: URL { documents.appendingPathComponent("images", isDirectory: true) }
    var trash: URL { documents.appendingPathComponent(".trash", isDirectory: true) }
    var conversations: URL { documents.appendingPathComponent("conversations.json") }
    var apiKeySeed: URL { documents.appendingPathComponent("seed_api_key.txt") }

    func image(_ name: String) -> URL { images.appendingPathComponent(name) }
    func trashItem(_ name: String) -> URL { trash.appendingPathComponent(name) }
    func imageURL(for attachment: Attachment) -> URL { image(attachment.file) }
}
