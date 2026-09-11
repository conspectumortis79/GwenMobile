import Foundation
import CoreGraphics

enum ImagePolicy {
    static let uploadByteBudget = 600_000
    static let uploadMaxPixel: CGFloat = 1568
    static let displayMaxPixel: CGFloat = 700
    static let photoExportMaxPixel: CGFloat = 1568
    static let viewerMaxPixel: CGFloat = 2000
    static let jpegQuality: CGFloat = 0.8
    static let cacheCostFactor = 4
    static let memoryCostLimit = 128 * 1024 * 1024
}
