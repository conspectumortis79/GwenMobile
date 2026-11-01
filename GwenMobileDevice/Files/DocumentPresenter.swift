@testable import GwenMobileFeatureCore
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DocumentPresenter: NSObject, ObservableObject, UIDocumentPickerDelegate {
    static let shared = DocumentPresenter()

    var onURLs: (([URL]) -> Void)?

    private var picker: UIDocumentPickerViewController?

    func present() {
        present(types: FileKind.importTypes)
    }

    func presentVideo() {
        present(types: FileKind.videoImportTypes)
    }

    private func present(types: [UTType]) {
        guard picker == nil else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        guard Presenter.presentIfPossible(picker) else { return }
        self.picker = picker
    }

    #if DEBUG
    func close() {
        guard picker != nil else { return }
        picker = nil
        Presenter.topViewController?.dismiss(animated: true)
    }
    #endif

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        picker = nil
        onURLs?(urls)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        picker = nil
        onURLs?([url])
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        picker = nil
    }
}
