import GwenMobileKit
import UIKit
import Vision

enum TextRecognizing {
    static func textRequest(languages: [String]) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        return request
    }

    static func recognize(data: Data, languages: [String]) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return recognize(image: image, languages: languages)
    }

    static func recognize(image: UIImage, languages: [String]) -> String? {
        guard let cg = image.cgImage else { return nil }
        return recognize(cgImage: cg, languages: languages)
    }

    static func recognize(cgImage: CGImage, languages: [String]) -> String? {
        let request = textRequest(languages: languages)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return text(from: request.results)
    }

    static func text(from results: [VNRecognizedTextObservation]?) -> String? {
        let lines = (results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        let joined = lines.joined(separator: "\n").trimmed
        return joined.isEmpty ? nil : joined
    }

    static var languages: [String] {
        switch L.lang {
        case .de: return ["de-DE", "en-US"]
        case .en: return ["en-US", "de-DE"]
        case .es: return ["es-ES", "en-US", "de-DE"]
        case .fr: return ["fr-FR", "en-US", "de-DE"]
        }
    }
}
