import Foundation

enum FilePolicy {
    static let maxFilesPerMessage = 5
    static let maxFileBytes = 20_000_000
    static let maxVideoBytes = 100_000_000
    static let maxTextChars = 24_000
    static let maxPDFPages = 100
    static let maxOCRPages = 8
    static let maxContextChars = 48_000
    static let ocrRenderScale: CGFloat = 2
    static let ocrPageWidth: CGFloat = 1200
    static let ocrPageHeight: CGFloat = 1_684
    static let maxOCRPagePixels = 8_000_000
}
