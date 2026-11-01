import GwenMobileKit
import SwiftUI

struct GalleryBarPlan: Equatable {
    let selected: Int
    let total: Int
    let progress: GalleryProgress?
    let result: GalleryResult?

    var canAct: Bool { progress == nil && selected > 0 }
    var showsSaveAll: Bool { total > 0 && selected > 0 && selected < total }
    var isConfirmation: Bool { selected == 0 && result != nil }

    var resultSymbol: String {
        if case .saved = result { return "checkmark.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    var resultTint: Color {
        if case .saved = result { return Color(.systemGreen) }
        return Color(.systemRed)
    }

    var statusLine: String {
        if let progress { return L.fmt2("pictures_saving", String(progress.done), String(progress.total)) }
        if let result { return resultLine(result) }
        return L.n("pictures_selected", selected)
    }

    var saveTitle: String {
        selected > 1 ? L.n("pictures_save_count", selected) : L.t("save_to_photos")
    }

    var saveAllTitle: String { L.n("pictures_save_all_count", total) }
    var shareTitle: String { L.t("pictures_share") }
    var cancelTitle: String { L.t("cancel") }
    var shortcutLine: String { L.t("pictures_shortcuts") }

    static func make(selected: Int, total: Int, progress: GalleryProgress?,
                     result: GalleryResult?) -> GalleryBarPlan {
        GalleryBarPlan(selected: selected, total: total, progress: progress, result: result)
    }

    private func resultLine(_ result: GalleryResult) -> String {
        switch result {
        case .saved(let count): return L.counted(count, one: "image_saved", many: "pictures_saved_all")
        case .denied: return L.t("photos_not_allowed")
        case .failed: return L.t("save_failed")
        }
    }
}
