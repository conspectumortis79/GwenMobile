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
    static func instructions(pictures count: Int, shown: [Int], total: Int) -> String {
        """
        You are shown pictures of one chat, each introduced by a label BILD n in the order given (1 is the first picture shown to you, \(count) the last). Their places inside the chat are \(shown.map(String.init).joined(separator: ", ")) of \(total) pictures, in that same order, and the chat's very first picture is BILD 1 whenever it is shown at all. Some labels add "(just sent by the user)": that is a picture the user attached to the current request.
        Decide which single picture the request wants changed. Weigh the user's wording against the chat places above: when the picture the user names is not among the shown ones, answer {"edit":null} and nothing else.
        Reply with ONLY one JSON object: {"edit":n,"reference":n,"instruction":"..."}
        "edit" is the number of the picture to change, "reference" the number of the template picture or null when none is needed, and "instruction" the change written for the picture named in "edit".
        In "instruction" never use picture numbers: call the picture to change "the target image" and the template "the template", keep the language of the user's request, and write the instruction so complete that the generation model does not need the template in front of it: name the taken property in exact concrete words (the dark antracite grey of the template, the mustard yellow of its star, the object filling about two thirds of the height), name the property of the *object* that is named rather than the picture's background, and say what must stay exactly as it is in the target image — its own outline, its own shape, its position and its background, unless the request changes them.
        """
    }

    static func label(number: Int, fresh: [Int]) -> String {
        fresh.contains(number) ? "BILD \(number) (just sent by the user)" : "BILD \(number)"
    }

    static func request(baseURL: String, key: String, model: String, instruction: String,
                        pictures: [Data], shown: [Int] = [], total: Int = 0, fresh: [Int] = [],
                        thinking: ThinkingDirective = .nothing) throws -> URLRequest {
        let shown = shown.isEmpty ? pictures.indices.map { $0 + 1 } : shown
        var parts: [[String: Any]] = [[
            "type": "text",
            "text": instructions(pictures: pictures.count, shown: shown,
                                 total: max(total, shown.count)) + "\n\nANFRAGE: " + instruction,
        ]]
        for (index, picture) in pictures.enumerated() {
            let number = index + 1
            parts.append(["type": "text", "text": label(number: number, fresh: fresh)])
            parts.append(["type": "image_url", "image_url": ["url": QwenAPI.dataURL(picture)]])
        }
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": parts]],
        ]
        thinking.applied(to: &body)
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.chatRequest)
    }

    static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let doubled = number.doubleValue
            return doubled.isFinite ? Int(doubled) : nil
        }
        if let digits = value as? String {
            return Int(digits.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func direction(from raw: String?, pictures count: Int) -> PictureDirection? {
        guard count > 1, let raw, let object = JSONFragment.object(from: raw),
              let edit = object["edit"] else { return nil }
        if edit is NSNull { return .unreachable }
        let text = (object["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = number(edit), (1...count).contains(target),
              let instruction = text, !instruction.isEmpty else { return nil }
        let reference = number(object["reference"]).flatMap { (1...count).contains($0) && $0 != target ? $0 : nil }
        return .edit(target: target, reference: reference, instruction: instruction)
    }

    static func observe(baseURL: String, key: String, model: String, instruction: String,
                        pictures: [Data], shown: [Int] = [], total: Int = 0, fresh: [Int] = [],
                        thinking: ThinkingDirective = .nothing) async -> PictureDirection? {
        let raw = try? await Offload.run {
            let probe = try PictureDirector.request(baseURL: baseURL, key: key, model: model,
                                                    instruction: instruction, pictures: pictures, shown: shown,
                                                    total: total, fresh: fresh, thinking: thinking)
            return try await QwenAPI.askText(probe)
        }
        guard let raw else { return nil }
        guard let direction = direction(from: raw, pictures: pictures.count) else {
            flowMark("BILDZIEL unverwertet bilder=\(pictures.count) \"\(instruction)\" antwort="
                     + raw.replacingOccurrences(of: "\n", with: " ").prefix(120))
            return nil
        }
        flowMark("BILDZIEL \(direction.trace)")
        return direction
    }
}
