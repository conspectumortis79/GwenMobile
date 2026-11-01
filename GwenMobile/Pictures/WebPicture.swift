import GwenMobileKit
import Foundation

struct PictureHit: Sendable, Hashable {
    let thumbURL: String
    let pageURL: String
    let fullURL: String
    let title: String
    let domain: String
}

struct WebPicture: Codable, Hashable, Sendable {
    var file: String
    var pageURL: String
    var fullURL: String
    var title: String
    var domain: String

    enum CodingKeys: String, CodingKey {
        case file, pageURL, fullURL, title, domain
    }
}

extension WebPicture {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        file = fields.content(String.self, .file, fallback: "")
        pageURL = fields.content(String.self, .pageURL, fallback: "")
        fullURL = fields.content(String.self, .fullURL, fallback: "")
        title = fields.content(String.self, .title, fallback: "")
        domain = fields.content(String.self, .domain, fallback: "")
    }

    var attachment: Attachment { Attachment(file: file) }
    var source: WebSource { WebSource(title: title, url: pageURL, domain: domain) }
}

struct PictureGallery: Codable, Hashable, Sendable {
    var query: String
    var pictures: [WebPicture] = []
    var shown: Int = ImagePolicy.galleryInitialItems
    var nextOffset: Int = 1
    var exhausted: Bool = false

    enum CodingKeys: String, CodingKey {
        case query, pictures, shown, nextOffset, exhausted
    }

    var visiblePictures: [WebPicture] { Array(pictures.prefix(max(1, shown))) }
    var hiddenCount: Int { max(0, pictures.count - max(1, shown)) }
    var files: [String] { pictures.map(\.file) }
}

extension PictureGallery {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        query = fields.content(String.self, .query, fallback: "")
        pictures = fields.content([WebPicture].self, .pictures, fallback: []).filter { !$0.file.isEmpty }
        let initial = ImagePolicy.galleryInitialItems
        let storedShown = fields.content(Int.self, .shown, fallback: initial)
        shown = min(max(storedShown, 1), pictures.count + initial)
        nextOffset = max(1, fields.content(Int.self, .nextOffset, fallback: 1))
        exhausted = fields.content(Bool.self, .exhausted, fallback: false)
    }

    func revealingMore() -> PictureGallery {
        var copy = self
        copy.shown = min(pictures.count + ImagePolicy.galleryInitialItems,
                         shown + ImagePolicy.galleryInitialItems)
        return copy
    }

    var chipSources: [WebSource] {
        var seen = Set<String>()
        var chips: [WebSource] = []
        for picture in pictures where !seen.contains(picture.domain) {
            seen.insert(picture.domain)
            chips.append(picture.source)
            if chips.count == ImagePolicy.gallerySourceChips { break }
        }
        return chips
    }

    func merging(_ round: PictureRound) -> PictureGallery {
        var copy = self
        let known = Set(pictures.map(\.file))
        copy.pictures = pictures + round.pictures.filter { !known.contains($0.file) }
        copy.shown = max(shown, copy.pictures.count)
        copy.nextOffset = round.nextOffset
        copy.exhausted = round.exhausted
        return copy
    }
}

struct PictureRound: Sendable {
    let pictures: [WebPicture]
    let nextOffset: Int
    let exhausted: Bool
    let failures: Int
}
