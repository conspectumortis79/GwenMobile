@testable import GwenMobileFeatureCore
import AVFoundation
import CoreVideo
import XCTest

final class VideoCompressionTests: XCTestCase {
    func testTheFileLengthLimitFollowsDurationAndStaysInsideItsBounds() {
        XCTAssertEqual(VideoCompression.fileLengthLimit(seconds: 15), 3_000_000)
        XCTAssertEqual(VideoCompression.fileLengthLimit(seconds: 1), 1_500_000)
        XCTAssertEqual(VideoCompression.fileLengthLimit(seconds: 600), 20_000_000)
    }

    func testExportWritesASmallerPlayableVideoWithTheSameDuration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let source = try makeVideo(in: folder)
        let target = folder.appendingPathComponent("compressed.mp4")
        try await VideoCompression.export(from: source, to: target)
        let sourceSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int
        let targetSize = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int
        XCTAssertGreaterThan(targetSize ?? 0, 0)
        XCTAssertLessThanOrEqual(targetSize ?? 0, sourceSize ?? 0)
        let asset = AVURLAsset(url: target)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let size = try await tracks[0].load(.naturalSize)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1280)
        XCTAssertTrue(VideoBytes.isVideo(try Data(contentsOf: target)))
    }

    private func makeVideo(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("source.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 360,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let buffer = try pixelBuffer(from: adaptor, frame: frame)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame),
                                                                              timescale: 30)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    private func pixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor,
                             frame: Int) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw VideoCompressionError.status }
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
              let buffer = created else {
            throw VideoCompressionError.status
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw VideoCompressionError.status
        }
        var state = UInt32(truncatingIfNeeded: frame &+ 1)
        for index in 0..<CVPixelBufferGetDataSize(buffer) {
            state = state &* 1664525 &+ 1013904223
            base[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        return buffer
    }
}
