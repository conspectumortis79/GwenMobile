import UIKit
import ImageIO

final class MediaStore: @unchecked Sendable {
    let paths: StoragePaths

    private let fileManager: FileManager

    nonisolated(unsafe) private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = ImagePolicy.memoryCostLimit
        return cache
    }()

    private static let ratios = RatioStore()

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func prepareDirectories() {
        try? fileManager.createDirectory(at: paths.images, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: paths.trash, withIntermediateDirectories: true)
    }

    func store(_ image: UIImage) -> String? {
        guard let data = Self.encoded(image) else { return nil }
        return storeImageData(data)
    }

    func storeImageData(_ data: Data) -> String? {
        let name = "img_\(UUID().uuidString.prefix(12)).jpg"
        do { try Self.apiData(data).write(to: paths.image(name)); return name }
        catch { return nil }
    }

    func data(named file: String) -> Data? {
        fileManager.contents(atPath: paths.image(file).path)
    }

    func data(for attachment: Attachment) -> Data? {
        data(named: attachment.file)
    }

    func storedURL(for attachment: Attachment) -> URL? {
        let url = paths.imageURL(for: attachment)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func imageFileNames() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: paths.images.path))?
            .filter { $0.hasPrefix("img_") && $0.hasSuffix(".jpg") } ?? []
    }

    func byteSize(of file: String) -> Int {
        let attrs = try? fileManager.attributesOfItem(atPath: paths.image(file).path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    func moveImagesToTrash(_ files: [String]) -> [String] {
        var moved: [String] = []
        for file in files {
            let name = "\(UUID().uuidString.prefix(8))_\(file)"
            do {
                try fileManager.moveItem(at: paths.image(file), to: paths.trashItem(name))
                moved.append(name)
                Self.ratios.drop(file)
                Self.imageCache.removeObject(forKey: file as NSString)
            } catch { continue }
        }
        return moved
    }

    func restoreFromTrash(_ trashed: [String]) {
        for name in trashed {
            guard let file = name.split(separator: "_", maxSplits: 1).last else { continue }
            let target = paths.image(String(file))
            try? fileManager.moveItem(at: paths.trashItem(name), to: target)
        }
    }

    func emptyTrash() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: paths.trash.path) else { return }
        for name in names { try? fileManager.removeItem(at: paths.trashItem(name)) }
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
        var ratio: CGFloat = 1
        if let src = CGImageSourceCreateWithURL(paths.imageURL(for: Attachment(file: file)) as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           width > 0, height > 0 {
            ratio = CGFloat(width / height)
        }
        Self.ratios.setValue(ratio, for: file)
        return ratio
    }

    static func apiData(_ data: Data) -> Data {
        data.count > ImagePolicy.uploadByteBudget ? (normalizedJPEGData(data) ?? data) : data
    }

    static func normalizedJPEGData(_ data: Data) -> Data? {
        guard let img = thumbnail(data, maxPixel: ImagePolicy.uploadMaxPixel) else { return nil }
        return img.jpegData(compressionQuality: ImagePolicy.jpegQuality)
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

    static func encoded(_ image: UIImage) -> Data? {
        let scale = min(1, ImagePolicy.uploadMaxPixel / max(image.size.width, image.size.height))
        var img = image
        if scale < 1 {
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return img.jpegData(compressionQuality: ImagePolicy.jpegQuality)
    }
}
