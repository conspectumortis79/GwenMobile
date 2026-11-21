import AVFoundation
import Foundation

enum VideoCompressionError: Error {
    case duration
    case preset
    case empty
}

enum VideoCompression {
    static let targetBitsPerSecond: Double = 1_600_000
    static let maximumBytes: Int64 = 20_000_000
    static let minimumBytes: Int64 = 1_500_000
    static let minimumSourceBytes = 3_000_000

    #if DEBUG
    nonisolated(unsafe) static var makeSession: (AVAsset) -> AVAssetExportSession? = { asset in
        AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)
    }
    #else
    private static func makeSession(_ asset: AVAsset) -> AVAssetExportSession? {
        AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)
    }
    #endif

    static func fileLengthLimit(seconds: Double) -> Int64 {
        let bytes = (seconds * targetBitsPerSecond / 8).rounded()
        guard bytes.isFinite else { return maximumBytes }
        let clamped = min(Double(maximumBytes), max(Double(minimumBytes), bytes))
        return Int64(clamped)
    }

    static func export(from source: URL, to target: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw VideoCompressionError.duration }
        guard let session = Self.makeSession(asset) else {
            throw VideoCompressionError.preset
        }
        session.fileLengthLimit = fileLengthLimit(seconds: seconds)
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: target, as: .mp4)
    }
}
