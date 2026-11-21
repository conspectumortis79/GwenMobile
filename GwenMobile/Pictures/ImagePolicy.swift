import Foundation
import CoreGraphics

enum ImagePolicy {
    static let uploadByteBudget = 600_000
    static let uploadMaxPixel: CGFloat = 1568
    static let displayMaxPixel: CGFloat = 700
    static let photoExportMaxPixel: CGFloat = 1568
    static let viewerMaxPixel: CGFloat = 2000
    static let jpegQuality: CGFloat = 0.8
    static let uploadQualitySteps: [CGFloat] = [0.8, 0.6]
    static let uploadSideSteps: [CGFloat] = [1568, 1176, 882]
    static let storedByteBudget = 4_000_000
    static let cacheCostFactor = 4
    static let memoryCostLimit = 128 * 1024 * 1024
    static let maxAttachmentsPerMessage = 10
    static let rememberedPictures = 10
    static let galleryPageSpan = 24
    static let galleryMaxStored = 18
    static let galleryInitialItems = 12
    static let galleryThumbPixel = 720
    static let galleryDownloadWindow = 4
    static let gallerySourceChips = 6
    static let galleryTilesPerRow = 3
    static let galleryTileSide: CGFloat = 104
    static let galleryTileGap: CGFloat = 5
    static let galleryTileCorner: CGFloat = 9
    static let galleryLoadingPlaceholders = 3
    static let galleryChainPictures = rememberedPictures
    static let galleryHandleFont: CGFloat = 13
}
