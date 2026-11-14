import GwenMobileKit

struct MusicLibraryEntry: Equatable, Sendable {
    let kind: MusicKind
    let id: UInt64
    let name: String
    var artist: String?

    var pick: MusicPick { MusicPick(kind: kind, name: name, artist: artist) }
}

enum MusicLibraryMatching {
    static let searchOrder: [MusicKind] = [.playlist, .artist, .album, .song]

    static func kinds(for request: MusicRequest) -> [MusicKind] {
        request.kind == .any ? searchOrder : [request.kind]
    }

    static func best(for request: MusicRequest, in entries: [MusicLibraryEntry]) -> MusicLibraryEntry? {
        let wanted = ContactWords.words(request.term)
        guard !wanted.isEmpty else { return nil }
        let artist = request.query == nil ? [] : ContactWords.words(request.artist ?? "")
        for kind in kinds(for: request) {
            let ofKind = entries.filter { $0.kind == kind && fitsArtist($0, artist) }
            if let exact = ofKind.first(where: { ContactWords.words($0.name) == wanted }) { return exact }
            if let close = ofKind.first(where: {
                ContactWords.allFound(wanted, among: ContactWords.words($0.name), tolerant: false)
            }) { return close }
        }
        return nil
    }

    private static func fitsArtist(_ entry: MusicLibraryEntry, _ artist: [String]) -> Bool {
        guard !artist.isEmpty, entry.kind == .song || entry.kind == .album else { return true }
        return ContactWords.allFound(artist, among: ContactWords.words(entry.artist ?? ""), tolerant: false)
    }
}
