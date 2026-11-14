import GwenMobileKit
import Foundation

struct CodeFileExporter {
    private let paths: StoragePaths
    private let fileManager: FileManager

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func write(_ block: CodeBlock, question: String?, date: Date = Date()) throws -> URL {
        let naming = ArtifactNaming(directory: paths.code, fileExtension: block.language.fileExtension,
                                    fallbackPrefix: block.language.fileExtension, fileManager: fileManager)
        let url = try naming.prepare(question: question, date: date)
        try (block.code + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
