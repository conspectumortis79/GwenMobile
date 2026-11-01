import GwenMobileKit
import Foundation

struct WishPart: Equatable, Sendable {
    var text: String
    var independent: Bool
    var place: String? = nil
    var list: String? = nil
    var placeKnown = false
    var listKnown = false
    var isVideo = false
    var videoSeconds: Int? = nil
    var videoRatio: VideoRatio? = nil
}

struct WishList: Decodable, Equatable {
    var wishes: [String]
    var independent: [Int]
    var places: [String?]
    var lists: [String?]
    var videos: [Int]
    var videoSeconds: [String?]
    var videoRatios: [String?]

    private enum Keys: String, CodingKey {
        case wishes
        case independent
        case places
        case lists
        case videos
        case videoSeconds = "video_seconds"
        case videoRatios = "video_ratios"
    }

    init(wishes: [String], independent: [Int] = [], places: [String?] = [], lists: [String?] = [],
         videos: [Int] = [], videoSeconds: [String?] = [], videoRatios: [String?] = []) {
        self.wishes = wishes
        self.independent = independent
        self.places = places
        self.lists = lists
        self.videos = videos
        self.videoSeconds = videoSeconds
        self.videoRatios = videoRatios
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        wishes = try container.decode([String].self, forKey: .wishes)
        independent = (try? container.decode([Int].self, forKey: .independent))
            ?? (try? container.decode([String].self, forKey: .independent).compactMap(Int.init))
            ?? []
        places = (try? container.decode([String?].self, forKey: .places)) ?? []
        lists = (try? container.decode([String?].self, forKey: .lists)) ?? []
        videos = (try? container.decode([Int].self, forKey: .videos))
            ?? (try? container.decode([String].self, forKey: .videos).compactMap(Int.init))
            ?? []
        videoSeconds = (try? container.decode([String?].self, forKey: .videoSeconds))
            ?? (try? container.decode([Int?].self, forKey: .videoSeconds).map { $0.map(String.init) })
            ?? []
        videoRatios = (try? container.decode([String?].self, forKey: .videoRatios)) ?? []
    }
}

enum WishSplitter {
    static let maxTokens = 4000

    static func system() -> String {
        PromptLibrary.text("wish_splitter")
    }

    static func request(baseURL: String, key: String, model: String, text: String,
                        thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(system()), ChatPayload.user(text)],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             extra: ["max_tokens": maxTokens])
    }

    static func splitParts(asking ask: @escaping @Sendable () async throws -> String?,
                           knownLists: [String] = []) async -> [WishPart]? {
        let answer: String?
        do {
            answer = try await RateLimitRetry.run({ try await ask() })
        } catch {
            flowMark("ZERLEGUNG fehler " + TextLine.oneLine(error.localizedDescription, limit: 160))
            return nil
        }
        guard let found = parse(answer, knownLists: knownLists) else {
            flowMarkPersonal("ZERLEGUNG unlesbar zeichen=\(answer?.count ?? -1) "
                             + "anfang=\(TextLine.oneLine(answer ?? "-", limit: 160))")
            return nil
        }
        if found.truncated {
            flowMark("ZERLEGUNG abgeschnitten gerettet=\(found.parts.count)")
        }
        return found.parts
    }

    static func parse(_ answer: String?, knownLists: [String] = []) -> (parts: [WishPart], truncated: Bool)? {
        guard let answer, let found = decoded(answer) else { return nil }
        let kept = found.listed.wishes.enumerated().compactMap { index, text -> WishPart? in
            let trimmed = text.trimmed
            guard !trimmed.isEmpty else { return nil }
            let place = scope(found.listed.places, index)
            let list = listScope(found.listed.lists, index, knownLists: knownLists)
            let seconds = scope(found.listed.videoSeconds, index).value.flatMap(Int.init)
            let ratio = scope(found.listed.videoRatios, index).value.flatMap(VideoRatio.init(rawValue:))
            return WishPart(text: trimmed, independent: found.listed.independent.contains(index + 1),
                            place: place.value, list: list.value,
                            placeKnown: place.known, listKnown: list.known,
                            isVideo: found.listed.videos.contains(index + 1),
                            videoSeconds: seconds, videoRatio: ratio)
        }
        return kept.isEmpty ? nil : (kept, found.truncated)
    }

    private static func scope(_ values: [String?], _ index: Int) -> (value: String?, known: Bool) {
        guard index < values.count else { return (nil, false) }
        let value = values[index]?.trimmed
        return (value?.isEmpty == false ? value : nil, true)
    }

    private static func listScope(_ values: [String?], _ index: Int,
                                  knownLists: [String]) -> (value: String?, known: Bool) {
        let found = scope(values, index)
        guard found.known, let value = found.value else { return found }
        guard !knownLists.isEmpty else { return found }
        guard case .title(let name) = ReminderListChoice.resolve(requested: value, available: knownLists,
                                                                 deviceDefault: nil,
                                                                 silent: .keepCurrent) else {
            return (nil, false)
        }
        return (name, true)
    }

    private static func decoded(_ answer: String) -> (listed: WishList, truncated: Bool)? {
        if let listed = JSONFragment.decode(WishList.self, from: answer) {
            return (listed, false)
        }
        let rescued = TruncatedStringList.strings(under: "wishes", in: answer)
        guard !rescued.isEmpty else { return nil }
        return (WishList(wishes: rescued), true)
    }
}
