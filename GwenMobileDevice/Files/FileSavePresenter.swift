import GwenMobileKit
import UIKit

@MainActor
final class FileSavePresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = FileSavePresenter()

    private var picker: UIDocumentPickerViewController?
    private var temporaryURL: URL?
    private var onFinish: ((Bool) -> Void)?

    func present(url: URL, suggestedName: String, onFinish: @escaping (Bool) -> Void) {
        guard picker == nil else { return }
        let name = Self.exportName(suggestedName, fallback: url.lastPathComponent)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: temporary)
        do {
            try FileManager.default.copyItem(at: url, to: temporary)
        } catch {
            onFinish(false)
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: [temporary], asCopy: true)
        picker.delegate = self
        guard Presenter.presentIfPossible(picker) else {
            try? FileManager.default.removeItem(at: temporary)
            onFinish(false)
            return
        }
        self.picker = picker
        temporaryURL = temporary
        self.onFinish = onFinish
    }

    static func exportName(_ suggested: String, fallback: String) -> String {
        let cleaned = suggested
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmed
        return cleaned.isEmpty ? fallback : cleaned
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(false)
    }

    private func finish(_ saved: Bool) {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        temporaryURL = nil
        picker = nil
        let callback = onFinish
        onFinish = nil
        callback?(saved)
    }
}
