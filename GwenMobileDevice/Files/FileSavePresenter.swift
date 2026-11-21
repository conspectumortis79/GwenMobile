import GwenMobileKit
import UIKit

@MainActor
final class FileSavePresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = FileSavePresenter()

    private let sheet = SheetPresenter()
    private var temporaryURL: URL?
    private var onFinish: ((Bool) -> Void)?

    func present(url: URL, suggestedName: String, onFinish: @escaping (Bool) -> Void) {
        guard sheet.isFree else {
            onFinish(false)
            return
        }
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
        guard sheet.show(picker, onDismiss: { [weak self] in self?.finish(false) }) else {
            try? FileManager.default.removeItem(at: temporary)
            onFinish(false)
            return
        }
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
        sheet.release()
        let callback = onFinish
        onFinish = nil
        callback?(saved)
    }
}
