import UIKit
import UniformTypeIdentifiers

@MainActor
final class DocumentPresenter: NSObject, ObservableObject, UIDocumentPickerDelegate {
    static let shared = DocumentPresenter()

    var onURLs: (([URL]) -> Void)?

    private let sheet = SheetPresenter()

    func present() {
        present(types: FileKind.importTypes)
    }

    func presentVideo() {
        present(types: FileKind.videoImportTypes)
    }

    private func present(types: [UTType]) {
        guard sheet.isFree else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        sheet.show(picker)
    }

    #if DEBUG
    func close() {
        guard !sheet.isFree else { return }
        sheet.dismiss(animated: true)
    }
    #endif

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        sheet.release()
        onURLs?(urls)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        sheet.release()
        onURLs?([url])
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        sheet.release()
    }
}
