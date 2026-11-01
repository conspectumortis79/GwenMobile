#if DEBUG
import GwenMobileKit
import UIKit

enum ReceiptCard {
    static let receiptCanvas = CGSize(width: 1000, height: 700)
    static let receiptText = "ZWEI KAFFEE UND EIN STÜCK KUCHEN\nRECHNUNG: 14,80 EURO\nTISCH NUMMER SIEBEN"

    static func receiptCard(fontSize: CGFloat,
                            text: String = receiptText,
                            canvas: CGSize = receiptCanvas,
                            lineSpacing: CGFloat = 0,
                            rect: CGRect? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let area = rect ?? CGRect(x: 60, y: 140, width: canvas.width - 120, height: canvas.height - 280)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]
            if lineSpacing > 0 {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = lineSpacing
                attributes[.paragraphStyle] = paragraph
            }
            text.draw(in: area, withAttributes: attributes)
        }
    }
}
#endif
