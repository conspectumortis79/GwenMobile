import UIKit

@MainActor
protocol CodeFileExporting {
    func export(url: URL) throws
}

@MainActor
struct SystemCodeFileExporter: CodeFileExporting {
    func export(url: URL) throws {
        guard let host = Presenter.topViewController else { throw PresenterError.noHost }
        let sheet = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        Presenter.present(sheet, from: host)
    }
}
