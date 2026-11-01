import Foundation

enum FreeName {
    static func first<Candidate>(_ candidate: (Int?) -> Candidate, upTo limit: Int,
                                 isTaken: (Candidate) -> Bool) -> Candidate? {
        let plain = candidate(nil)
        guard isTaken(plain) else { return plain }
        for index in 2...limit {
            let numbered = candidate(index)
            if !isTaken(numbered) { return numbered }
        }
        return nil
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
