#if DEBUG
import GwenMobileKit
import UIKit

enum PixelBuffer {
    static func rgba(of image: UIImage, side: Int) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }
}
#endif
