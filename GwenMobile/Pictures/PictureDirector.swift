import GwenMobileKit
import Foundation

enum PictureDirection: Equatable, Sendable {
    case edit(target: Int, reference: Int?, instruction: String)
    case unreachable

    func pictures(from images: [Data]) -> [Data]? {
        guard case .edit(let target, _, _) = self, images.indices.contains(target - 1) else { return nil }
        return [images[target - 1]]
    }

    var trace: String {
        switch self {
        case .edit(let target, let reference, let instruction):
            return "ziel=\(target) vorlage=\(reference ?? -1) prompt=\(instruction.prefix(90))"
        case .unreachable:
            return "ziel=ausserhalb"
        }
    }
}

enum PictureDirector {
    static func label(number: Int, fresh: [Int] = []) -> String {
        var text = PromptLibrary.text("picture_label", ["picture_token": PromptToken.picture,
                                                        "number": String(number)])
        if fresh.contains(number) { text += " " + PromptLibrary.text("picture_label_fresh") }
        return text
    }

    static func request(baseURL: String, key: String, model: String, instruction: String,
                        pictures: [Data], fresh: [Int] = [],
                        thinking: ThinkingDirective) throws -> URLRequest {
        var parts: [[String: Any]] = [ChatPayload.text(
            Prompt.Pictures.director(pictures: pictures.count) + "\n\n"
                + PromptLibrary.text("picture_request", ["instruction": instruction]))]
        for (index, picture) in pictures.enumerated() {
            guard let encoded = ChatPayload.image(picture) else {
                throw APIError(message: L.t("image_too_large"))
            }
            parts.append(ChatPayload.text(label(number: index + 1, fresh: fresh)))
            parts.append(encoded)
        }
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                                    messages: [ChatPayload.user(parts)], stream: false,
                                    thinking: thinking, timeout: APITimeout.chatRequest,
                                    temperature: 0)
    }

    static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let doubled = number.doubleValue
            guard doubled.isFinite else { return nil }
            return Int(exactly: doubled.rounded(.towardZero))
        }
        if let digits = value as? String {
            return Int(digits.trimmed)
        }
        return nil
    }

    static func direction(from raw: String?, pictures count: Int) -> PictureDirection? {
        guard count > 1, let raw, let object = JSONFragment.object(from: raw),
              let edit = object["edit"] else { return nil }
        if edit is NSNull { return .unreachable }
        let text = (object["instruction"] as? String)?.trimmed
        guard let target = number(edit), (1...count).contains(target),
              let instruction = text, !instruction.isEmpty else { return nil }
        let reference = number(object["reference"]).flatMap { (1...count).contains($0) && $0 != target ? $0 : nil }
        return .edit(target: target, reference: reference, instruction: instruction)
    }

    static func observe(baseURL: String, key: String, model: String, instruction: String,
                        pictures: [Data], fresh: [Int] = [],
                        thinking: ThinkingDirective) async -> PictureDirection? {
        let raw = try? await Offload.run {
            let probe = try PictureDirector.request(baseURL: baseURL, key: key, model: model,
                                                    instruction: instruction, pictures: pictures,
                                                    fresh: fresh, thinking: thinking)
            return try await QwenAPI.askText(probe)
        }
        guard let raw else { return nil }
        guard let direction = direction(from: raw, pictures: pictures.count) else {
            flowMarkPersonal("BILDZIEL unverwertet bilder=\(pictures.count) \"\(instruction)\" antwort="
                     + raw.replacingOccurrences(of: "\n", with: " ").prefix(120))
            return nil
        }
        flowMarkPersonal("BILDZIEL \(direction.trace)")
        return direction
    }
}
