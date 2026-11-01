@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
protocol PictureDescribing {
    func describe(file: String) async -> String
}

@MainActor
struct VisionPictureDescriber: PictureDescribing {
    static let question = "Beschreibe in genau einem kurzen Satz auf Deutsch, was das Bild zeigt. Nenne ein "
        + "bekanntes Kunstwerk oder eine bekannte Person beim Namen, wenn du sie erkennst, nenne jedes Tier mit "
        + "seinem allgemeinen Wort (zum Beispiel Hund oder Katze) und nenne den Stil (Foto, Gemälde, Comic, "
        + "Zeichnung)."

    nonisolated static let failureMark = "FEHLER "
    static let attempts = 2

    let settings: AppSettings
    let media: MediaStore

    func describe(file: String) async -> String {
        guard let data = media.data(named: file) else { return Self.failureMark + "kein bild geladen" }
        var last = ""
        for attempt in 1...Self.attempts {
            do {
                return try await ask(about: file, data: data)
            } catch {
                last = error.localizedDescription
                if attempt < Self.attempts { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        return Self.failureMark + last
    }

    private func ask(about file: String, data: Data) async throws -> String {
        let model = settings.answeringModel(hasPictures: true)
        let req = try QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey, model: model,
                                          messages: [ChatMessage(role: .user, text: Self.question,
                                                                 images: [Attachment(file: file)])],
                                          imageData: [data],
                                          thinking: settings.thinkingOffDirective(for: model))
        return try await ChatRunner.shared.run(req) { _ in }
    }
}

enum PictureChroma {
    static let side = 32

    static func mean(of image: UIImage) -> Double {
        guard let pixels = PixelBuffer.rgba(of: image, side: side) else { return -1 }
        var total = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let channels = [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
            total += Int(channels.max() ?? 0) - Int(channels.min() ?? 0)
        }
        return Double(total) / Double(side * side)
    }
}

@MainActor
struct PictureInspector {
    let describer: any PictureDescribing
    let media: MediaStore

    func looks(at files: [String]) async -> [PictureLook] {
        var looks: [PictureLook] = []
        for file in files {
            let chroma = media.exportImage(named: file).map(PictureChroma.mean(of:)) ?? -1
            looks.append(PictureLook(chroma: chroma, description: await describer.describe(file: file)))
        }
        return looks
    }
}
#endif
