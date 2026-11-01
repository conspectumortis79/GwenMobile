@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import Foundation

enum CodeCardOutcome: Equatable {
    case nothing
    case notice(String)
    case preview(CodePreviewPage)
}

@MainActor
final class CodeCardActions {
    private let files: SavedCodeFiles
    private let presenter: CodeFilePresenting
    private let exporter: CodeFileExporting

    init(files: SavedCodeFiles = .shared,
         presenter: CodeFilePresenting = SystemCodeFilePresenter(),
         exporter: CodeFileExporting = SystemCodeFileExporter()) {
        self.files = files
        self.presenter = presenter
        self.exporter = exporter
    }

    func download(_ block: CodeBlock, question: String?) -> CodeCardOutcome {
        store(block, question: question) { url in
            try exporter.export(url: url)
            return .nothing
        }
    }

    func share(_ block: CodeBlock, question: String?) -> CodeCardOutcome {
        store(block, question: question) { url in
            try presenter.present(url: url)
            return .nothing
        }
    }

    func preview(_ block: CodeBlock, question: String?) -> CodeCardOutcome {
        store(block, question: question) { url in
            .preview(CodePreviewPage(url: url))
        }
    }

    private func store(_ block: CodeBlock, question: String?,
                       then: (URL) throws -> CodeCardOutcome) -> CodeCardOutcome {
        do {
            return try then(try files.url(for: block, question: question))
        } catch {
            return .notice(error.localizedDescription)
        }
    }
}
