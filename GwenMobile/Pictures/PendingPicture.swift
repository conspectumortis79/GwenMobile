import GwenMobileKit
import UIKit

struct PendingPicture: Identifiable {
    var id = UUID()
    let image: UIImage
    let file: String?
    var ocrFile: OcrFile? = nil
}
