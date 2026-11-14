import AVFoundation
import Foundation

enum VideoCompressionError: Error {
    case duration
    case preset
    case status
}

enum VideoCompression {
    static let targetBitsPerSecond: Double = 1_600_000
    static let maximumBytes: Int64 = 20_000_000
    static let minimumBytes: Int64 = 1_500_000
    static let minimumSourceBytes = 3_000_000

    static func fileLengthLimit(seconds: Double) -> Int64 {
        let wanted = Int64((seconds * targetBitsPerSecond / 8).rounded())
        return max(minimumBytes, min(maximumBytes, wanted))
    }

    static func export(from source: URL, to target: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw VideoCompressionError.duration }
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPreset1280x720) else {
            throw VideoCompressionError.preset
        }
        session.fileLengthLimit = fileLengthLimit(seconds: seconds)
        session.shouldOptimizeForNetworkUse = true
        #if targetEnvironment(macCatalyst)
        if #available(macOS 15.0, *) {
            try await session.export(to: target, as: .mp4)
        } else {
            try await legacyExport(session, to: target)
        }
        #else
        try await session.export(to: target, as: .mp4)
        #endif
    }

    #if targetEnvironment(macCatalyst)
    @available(iOS, introduced: 4.0, deprecated: 18.0)
    private static func legacyExport(_ session: AVAssetExportSession, to target: URL) async throws {
        session.outputURL = target
        session.outputFileType = .mp4
        let box = ExportSessionBox(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                if let error = box.session.error {
                    continuation.resume(throwing: error)
                } else if box.session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VideoCompressionError.status)
                }
            }
        }
    }
    #endif
}

#if targetEnvironment(macCatalyst)
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
#endif
