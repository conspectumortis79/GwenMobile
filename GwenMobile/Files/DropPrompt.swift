import GwenMobileKit
import Foundation

enum DropPrompt {
    static func text(pictures: Int, files: Int, videos: Int = 0) -> String {
        if videos > 0 {
            let hasOtherAttachments = pictures > 0 || files > 0
            if videos > 1 {
                return hasOtherAttachments ? L.t("drop_analyze_videos_mixed") : L.t("drop_analyze_videos")
            }
            return hasOtherAttachments ? L.t("drop_analyze_video_mixed") : L.t("drop_analyze_video")
        }
        if pictures > 0, files > 0 { return L.t("drop_analyze_mixed") }
        if pictures > 0 { return pictures > 1 ? L.t("drop_analyze_pictures") : L.t("drop_analyze_picture") }
        return files > 1 ? L.t("drop_analyze_files") : L.t("drop_analyze_file")
    }
}
