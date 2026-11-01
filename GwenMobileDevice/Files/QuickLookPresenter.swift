import GwenMobileKit
import UIKit
import QuickLook

final class FilePreviewItem: NSObject, QLPreviewItem, @unchecked Sendable {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL?, title: String?) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

@MainActor
final class QuickLookPresenter: NSObject, QLPreviewControllerDataSource {
    static let shared = QuickLookPresenter()

    private var items: [FilePreviewItem] = []

    func present(url: URL?, title: String?) {
        guard let url else { return }
        items = [FilePreviewItem(url: url, title: title)]
        let controller = QLPreviewController()
        controller.dataSource = self
        Presenter.presentIfPossible(controller)
    }

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewController(_ controller: QLPreviewController,
                                       previewItemAt index: Int) -> QLPreviewItem {
        MainActor.assumeIsolated { items[index] }
    }
}
