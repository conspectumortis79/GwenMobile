import GwenMobileKit
import Foundation
import NaturalLanguage
import Translation

enum OnDeviceStatus: Equatable {
    case ready
    case packMissing
    case unsupportedPair
}

enum TranslationProblem: Error, Equatable {
    case nothingToTranslate
    case packMissing(String)
    case unsupportedPair(String)
    case device(String)
    case model(String)
}

extension TranslationProblem {
    var copy: String {
        switch self {
        case .nothingToTranslate: return L.t("translate_no_text")
        case .packMissing(let code): return L.fmt("translate_pack_missing",
                                                                TranslationLanguages.named(code))
        case .unsupportedPair(let code): return L.fmt("translate_pair_unsupported",
                                                                    TranslationLanguages.named(code))
        case .device, .model: return L.t("translate_failed")
        }
    }

    var opensSettings: Bool {
        switch self {
        case .packMissing: return true
        case .nothingToTranslate, .unsupportedPair, .device, .model: return false
        }
    }

    var detail: String {
        switch self {
        case .device(let reason), .model(let reason): return reason
        case .nothingToTranslate, .packMissing, .unsupportedPair: return ""
        }
    }

    var alert: L.FriendlyError {
        switch self {
        case .model(let reason):
            let friendly = L.friendlyError(reason)
            return L.FriendlyError(message: friendly.message,
                                   detail: L.t("translate_failed"),
                                   openSettings: friendly.openSettings)
        default:
            return L.FriendlyError(message: copy, detail: detail, openSettings: opensSettings)
        }
    }

    static func from(status: OnDeviceStatus, target: String) -> TranslationProblem {
        switch status {
        case .ready: return .device("")
        case .packMissing: return .packMissing(target)
        case .unsupportedPair: return .unsupportedPair(target)
        }
    }
}

enum TranslationChunks {
    static let limit = 900

    static func split(_ text: String) -> [String] {
        pack(bounded(segments(text)))
    }

    static func segments(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var boundary = false
        for character in text {
            if boundary, !character.isWhitespace {
                out.append(current)
                current = ""
                boundary = false
            }
            current.append(character)
            if endsSegment(character) { boundary = true }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func endsSegment(_ character: Character) -> Bool {
        ".!?".contains(character) || character.isNewline
    }

    static func bounded(_ pieces: [String]) -> [String] {
        pieces.flatMap { piece in piece.count <= limit ? [piece] : hardSplit(piece) }
    }

    static func hardSplit(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while rest.count > limit {
            let cut = cutPoint(of: rest)
            out.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    private static func cutPoint(of text: Substring) -> Substring.Index {
        let head = text.prefix(limit)
        if let space = head.lastIndex(of: " ") { return text.index(space, offsetBy: 1) }
        return head.endIndex
    }

    static func pack(_ pieces: [String]) -> [String] {
        var out: [String] = []
        var current = ""
        for piece in pieces {
            if !current.isEmpty, current.count + piece.count > limit {
                out.append(current)
                current = piece
                continue
            }
            current += piece
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

enum OnDeviceTranslation {
    static let sourceAliases: [String: String] = [
        "no": "nb", "yue": "zh-Hant", "zh": "zh-Hans", "cmn": "zh-Hans", "zho": "zh-Hans",
        "ars": "ar", "fil": "en", "iw": "he", "pt-BR": "pt", "es-MX": "es", "en-GB": "en",
    ]

    static func detectedSource(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text).flatMap { normalized($0.rawValue) }
    }

    static func normalized(_ code: String) -> String? {
        if let alias = sourceAliases[code] { return alias }
        if let known = TranslationLanguages.withCode(code) { return known.code }
        let primary = String(code.split(separator: "-").first ?? Substring(code))
        if let alias = sourceAliases[primary] { return alias }
        return TranslationLanguages.withCode(primary)?.code
    }

    static func sourceCode(for job: TranslationJob) -> String {
        if let explicit = TranslationLanguages.withCode(job.sourceCode)?.code { return explicit }
        if let detected = detectedSource(of: job.text) { return detected }
        return L.lang.rawValue
    }

    static func stitch(chunks: [String], responses: [TranslationSession.Response]) -> String {
        var slots = chunks
        for response in responses {
            guard let identifier = response.clientIdentifier, let index = Int(identifier),
                  slots.indices.contains(index), !response.targetText.isEmpty else { continue }
            slots[index] = response.targetText
        }
        return slots.joined()
    }

    static func problem(for error: Error) -> TranslationProblem {
        let notInstalled = [TranslationError.notInstalled]
        if notInstalled.contains(where: { $0 ~= error }) { return .packMissing("") }
        let pairs = [TranslationError.unsupportedSourceLanguage,
                     TranslationError.unsupportedTargetLanguage,
                     TranslationError.unsupportedLanguagePairing]
        if pairs.contains(where: { $0 ~= error }) { return .unsupportedPair("") }
        return .device((error as? TranslationError)?.localizedDescription ?? error.localizedDescription)
    }
}
