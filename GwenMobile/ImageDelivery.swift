import Foundation

@MainActor
struct ImageDelivery {
    private let media: MediaStore

    init(media: MediaStore) { self.media = media }

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data] = [], isEdit: Bool = false) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let req = try QwenAPI.makeImageRequest(baseURL: baseURL, key: key, model: model,
                                                   prompt: prompt, inputImages: inputImages,
                                                   isEdit: isEdit)
            return try await QwenAPI.generateImage(req: req)
        }.value
    }

    func store(_ urls: [URL]) async throws -> [Attachment] {
        var attachments: [Attachment] = []
        for url in urls {
            let data = try await QwenAPI.download(url)
            if let name = media.storeImageData(data) { attachments.append(Attachment(file: name)) }
        }
        return attachments
    }
}
