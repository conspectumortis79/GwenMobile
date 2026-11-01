import GwenMobileKit
import CoreImage
import Foundation
import UIKit

@MainActor
struct ImageDelivery {
    private let media: MediaStore
    private let backend: any ImageGenerating

    nonisolated(unsafe) static var inflightRetrySeconds = 10

    init(media: MediaStore, backend: any ImageGenerating) {
        self.media = media
        self.backend = backend
    }

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data] = [], isEdit: Bool = false) async throws -> [GeneratedPicture] {
        let backend = self.backend
        return try await Offload.run {
            try await backend.generate(baseURL: baseURL, key: key, model: model, prompt: prompt,
                                       inputImages: inputImages, isEdit: isEdit)
        }
    }

    func makePicture(baseURL: String, key: String, model: String, prompt: String,
                     inputImages: [Data] = [], isEdit: Bool = false) async throws -> [Attachment] {
        let pictures = try await generated(baseURL: baseURL, key: key, model: model, prompt: prompt,
                                          inputImages: inputImages, isEdit: isEdit)
        let attachments = try await store(pictures)
        guard !attachments.isEmpty else { throw APIError(message: L.t("no_image")) }
        return attachments
    }

    private func generated(baseURL: String, key: String, model: String, prompt: String,
                           inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        var attempt = 1
        while true {
            do {
                return try await generate(baseURL: baseURL, key: key, model: model, prompt: prompt,
                                          inputImages: inputImages, isEdit: isEdit)
            } catch let error as APIError
                where (error.isRateLimited || error.isInflightCreditLimit)
                    && attempt < RateLimitRetry.attempts {
                let wait = error.isInflightCreditLimit
                    ? Duration.seconds(ImageDelivery.inflightRetrySeconds * attempt)
                    : RateLimitRetry.backoff * attempt
                flowMark("BILD warte \(wait) versuch=\(attempt) grund="
                         + (error.isInflightCreditLimit ? "inflight" : "drossel"))
                try await Task.sleep(for: wait)
                attempt += 1
            }
        }
    }

    func store(_ pictures: [GeneratedPicture]) async throws -> [Attachment] {
        try await store(pictures, download: QwenAPI.download)
    }

    func store(_ pictures: [GeneratedPicture],
               download: (URL) async throws -> Data) async throws -> [Attachment] {
        var attachments: [Attachment] = []
        let media = self.media
        do {
            for picture in pictures {
                let data: Data
                switch picture {
                case .remote(let url): data = try await download(url)
                case .inline(let bytes): data = bytes
                }
                if let name = try await Offload.run({ media.storeImageData(data) }) {
                    attachments.append(Attachment(file: name))
                }
            }
        } catch {
            let written = attachments.map(\.file)
            try? await Offload.run { media.discardStored(written) }
            throw error
        }
        return attachments
    }

    static func monochrome(_ data: Data) -> Data? {
        guard let image = CIImage(data: data),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: ImagePolicy.jpegQuality)
    }
}
