import GwenMobileKit
import Foundation

enum DropPrompt {
    static func text(pictures: Int, files: Int) -> String {
        if pictures > 0, files > 0 { return L.t("drop_analyze_mixed") }
        if pictures > 0 { return pictures > 1 ? L.t("drop_analyze_pictures") : L.t("drop_analyze_picture") }
        return files > 1 ? L.t("drop_analyze_files") : L.t("drop_analyze_file")
    }
}
