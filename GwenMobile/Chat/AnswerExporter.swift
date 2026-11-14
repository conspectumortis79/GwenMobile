import GwenMobileKit
import Foundation

struct AnswerExporter {
    private let naming: ArtifactNaming

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        naming = ArtifactNaming(directory: paths.answers, fileExtension: "html",
                                fallbackPrefix: "antwort", fileManager: fileManager)
    }

    func write(text: String, sources: [WebSource], question: String?, model: String? = nil,
               elapsed: Double? = nil, time: String? = nil, date: Date = Date()) throws -> URL {
        let url = try naming.prepare(question: question, date: date)
        let document = AnswerHTML.document(
            text: text,
            sources: sources,
            heading: L.t("web_sources_head"),
            title: question?.trimmed ?? "",
            meta: AnswerHTML.metaLine(model: model, elapsed: elapsed, time: time),
            language: L.lang.rawValue
        )
        try document.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
