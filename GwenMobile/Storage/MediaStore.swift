import GwenMobileKit
import UIKit
import ImageIO

final class MediaStore: @unchecked Sendable {
    let paths: StoragePaths

    private let fileManager: FileManager
    private let storage: FileStorage

    nonisolated(unsafe) private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = ImagePolicy.memoryCostLimit
        return cache
    }()

    private static let ratios = LockedDictionary<String, CGFloat>(capacity: 512)

    static let filePrefix = "img_"

    nonisolated(unsafe) static var jpegData: @Sendable (UIImage, CGFloat) -> Data? = { image, quality in
        image.jpegData(compressionQuality: quality)
    }

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        storage = FileStorage(layout: ImageLayout(paths: paths), fileManager: fileManager)
    }

    func prepareDirectories() {
        paths.moveSharedFoldersIntoAppStorage(fileManager)
        storage.prepare()
        try? fileManager.createDirectory(at: paths.support, withIntermediateDirectories: true)
    }

    func store(_ image: UIImage) -> String? {
        guard let data = Self.encoded(image) else { return nil }
        return write(data)
    }

    func storeImageData(_ data: Data) -> String? {
        guard let stored = Self.storableData(data) else { return nil }
        return write(stored)
    }

    private func write(_ data: Data) -> String? {
        let name = storage.layout.newName(PictureFormat.of(data).fileExtension)
        guard (try? data.write(to: storage.url(for: name))) != nil else { return nil }
        if let ratio = measuredRatio(of: name) { Self.ratios.setValue(ratio, for: name) }
        return name
    }

    func data(named file: String) -> Data? { storage.data(for: file) }

    func hasImage(_ file: String) -> Bool { storage.exists(file) }

    func data(for attachment: Attachment) -> Data? {
        data(named: attachment.file)
    }

    func storedURL(for attachment: Attachment) -> URL? {
        storage.storedURL(for: attachment.file)
    }

    func fileNames() -> [String] { storage.names() }

    func byteSize(of file: String) -> Int { storage.byteSize(of: file) }

    @discardableResult
    func moveImagesToTrash(_ files: [String]) -> [TrashedFile] {
        let moved = storage.moveToTrash(files)
        for entry in moved { forgetCaches(of: entry.file) }
        return moved
    }

    func restoreFromTrash(_ trashed: [TrashedFile]) { storage.restoreFromTrash(trashed) }

    func emptyTrash() { storage.emptyTrash() }

    func discardStored(_ files: [String]) {
        storage.discard(files)
        for file in files { forgetCaches(of: file) }
    }

    func discardTrashed(_ trashed: [TrashedFile]) { storage.discardTrashed(trashed) }

    private func forgetCaches(of file: String) {
        Self.ratios.removeValue(for: file)
        Self.imageCache.removeObject(forKey: file as NSString)
    }

    func cachedDisplayImage(named file: String) -> UIImage? {
        Self.imageCache.object(forKey: file as NSString)
    }

    func decodedDisplayImage(named file: String) -> UIImage? {
        let key = file as NSString
        if let hit = Self.imageCache.object(forKey: key) { return hit }
        #if DEBUG
        RenderStats.imageDecodes.bump()
        #endif
        guard let data = data(named: file),
              let img = Self.thumbnail(data, maxPixel: ImagePolicy.displayMaxPixel) else { return nil }
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * CGFloat(ImagePolicy.cacheCostFactor))
        Self.imageCache.setObject(img, forKey: key, cost: max(cost, 1))
        return img
    }

    func exportImage(named file: String) -> UIImage? {
        guard let data = data(named: file) else { return nil }
        return Self.thumbnail(data, maxPixel: ImagePolicy.photoExportMaxPixel)
    }

    func cachedDisplayRatio(named file: String) -> CGFloat? {
        Self.ratios.value(for: file)
    }

    func displayRatio(named file: String) -> CGFloat {
        if let hit = Self.ratios.value(for: file) { return hit }
        #if DEBUG
        RenderStats.ratioReads.bump()
        #endif
        guard let ratio = measuredRatio(of: file) else { return 1 }
        Self.ratios.setValue(ratio, for: file)
        return ratio
    }

    private func measuredRatio(of file: String) -> CGFloat? {
        guard let url = storage.storedURL(for: file),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        return CGFloat(width / height)
    }

    static func apiData(_ data: Data) -> Data? {
        data.count > ImagePolicy.uploadByteBudget
            ? boundedJPEGData(data, budget: ImagePolicy.uploadByteBudget) : data
    }

    static func storableData(_ data: Data) -> Data? {
        data.count > ImagePolicy.storedByteBudget
            ? boundedJPEGData(data, budget: ImagePolicy.storedByteBudget) : data
    }

    private static let fallbackSides: [CGFloat] = [720, 560, 420, 320, 240, 160, 100]
    private static let fallbackQualities: [CGFloat] = [0.6, 0.5, 0.4, 0.3, 0.2, 0.1]

    private static func boundedJPEGData(_ data: Data, budget: Int) -> Data? {
        guard let image = thumbnail(data, maxPixel: ImagePolicy.uploadMaxPixel) else { return nil }
        return encoded(image, budget: budget)
    }

    static func thumbnail(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func encoded(_ image: UIImage, budget: Int = ImagePolicy.uploadByteBudget) -> Data? {
        let ladders = [(ImagePolicy.uploadSideSteps, ImagePolicy.uploadQualitySteps),
                       (fallbackSides, fallbackQualities)]
        for (sides, qualities) in ladders {
            for side in sides {
                let candidate = fitted(image, longestSide: side)
                for quality in qualities {
                    guard let data = jpegData(candidate, quality) else { continue }
                    if data.count <= budget { return data }
                }
            }
        }
        return nil
    }

    private static func fitted(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide, longest > 0 else { return image }
        let scale = longestSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum PictureFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case gif
    case webp
    case heic

    static let headerSize = 16

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
        case .webp: return "webp"
        case .heic: return "heic"
        }
    }

    var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .gif: return "image/gif"
        case .webp: return "image/webp"
        case .heic: return "image/heic"
        }
    }

    static func of(_ data: Data) -> PictureFormat {
        let head = [UInt8](data.prefix(headerSize))
        if hasPrefix(head, [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if hasPrefix(head, [0x47, 0x49, 0x46, 0x38]) { return .gif }
        if hasPrefix(head, [0x52, 0x49, 0x46, 0x46]) && bytes(head, at: 8, are: [0x57, 0x45, 0x42, 0x50]) {
            return .webp
        }
        if bytes(head, at: 4, are: [0x66, 0x74, 0x79, 0x70]),
           ["heic", "heix", "heim", "mif1"].contains(ascii(head, from: 8, to: 12)) { return .heic }
        return .jpeg
    }

    private static func hasPrefix(_ head: [UInt8], _ marker: [UInt8]) -> Bool {
        head.count >= marker.count && Array(head.prefix(marker.count)) == marker
    }

    private static func bytes(_ head: [UInt8], at start: Int, are marker: [UInt8]) -> Bool {
        head.count >= start + marker.count && Array(head[start..<(start + marker.count)]) == marker
    }

    private static func ascii(_ head: [UInt8], from start: Int, to end: Int) -> String {
        guard head.count >= end else { return "" }
        return String(decoding: head[start..<end], as: UTF8.self)
    }
}
