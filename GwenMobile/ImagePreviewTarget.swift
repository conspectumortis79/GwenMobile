import Foundation

struct ImagePreviewTarget: Identifiable, Equatable, Sendable {
    let files: [String]
    let startIndex: Int

    var id: String { files.joined(separator: "|") + "#\(startIndex)" }

    init?(tappedFile: String, files: [String]) {
        guard let index = files.firstIndex(of: tappedFile) else { return nil }
        self.files = files
        self.startIndex = index
    }
}
