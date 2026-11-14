#if DEBUG
@testable import GwenMobileFeatureCore
#if DEBUG
import AVFoundation
import CoreVideo
import Foundation
import GwenMobileKit

private enum DebugVideoCompressionError: Error {
    case writer
    case pool
    case staging
    case route
}

@MainActor
enum DebugVideoCompressionProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "video_compress_probe.txt")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwen-video-compress-\(UUID().uuidString)")
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        let savedVideoModel = view.settings.videoModel
        let probeSource = StoragePaths().documents.appendingPathComponent("video_probe_source.mp4")
        let usesProvidedSource = FileManager.default.fileExists(atPath: probeSource.path)
        view.pendingFiles = []
        view.pendingImages = []
        defer {
            for file in view.pendingFiles { view.store.documents.discardStored([file.file]) }
            view.settings.videoModel = savedVideoModel
            view.pendingFiles = []
            view.pendingImages = []
            _ = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
            try? FileManager.default.removeItem(at: folder)
            if usesProvidedSource { try? FileManager.default.removeItem(at: probeSource) }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let source = usesProvidedSource ? probeSource : try await Offload.run(priority: .userInitiated) {
                try makeVideo(in: folder)
            }
            let sourceSize = size(of: source)
            report.add("QUELLE", "echt=\(usesProvidedSource) bytes=\(sourceSize) "
                       + "bereit=\(sourceSize > VideoCompression.minimumSourceBytes)")
            let clock = ContinuousClock()
            let started = clock.now
            let target = folder.appendingPathComponent("compressed.mp4")
            try await VideoCompression.export(from: source, to: target)
            let targetSize = size(of: target)
            report.add("KOMPRIMIERT", "bytes=\(targetSize) dauer_ms=\(msOf(started.duration(to: .now))) "
                       + "kleiner=\(targetSize > 0 && targetSize < sourceSize)")
            let asset = AVURLAsset(url: target)
            let seconds = try await asset.load(.duration).seconds
            let track = try await asset.loadTracks(withMediaType: .video).first
            let box = try await track?.load(.naturalSize) ?? .zero
            report.add("VIDEO", "dauer=\(String(format: "%.2f", seconds)) "
                       + "breite=\(Int(box.width)) hoehe=\(Int(box.height)) "
                       + "header=\(VideoBytes.isVideo(try Data(contentsOf: target)))")

            let paths = StoragePaths()
            let analysis = VideoAnalysisStore(directory: paths.videoAnalysis)
            let documents = DocumentStore(paths: paths, videoAnalysis: analysis)
            documents.prepareDirectories()
            guard let stored = documents.store(url: source) else { throw DebugVideoCompressionError.staging }
            let compressed = await documents.analysisVideoData(for: stored.file)
            let cache = analysis.targetURL(for: stored.file)
            report.add("ABLAGE", "quelle=\(stored.file) bytes=\(stored.bytes) "
                       + "analyse_bytes=\(compressed?.count ?? -1) "
                       + "cache=\(FileManager.default.fileExists(atPath: cache.path))")
            let repeated = await documents.analysisVideoData(for: stored.file)
            report.add("CACHE", "gleich=\(compressed == repeated) "
                       + "cache=\(FileManager.default.fileExists(atPath: cache.path))")

            view.store.newConversation()
            guard let staged = await view.stageFile(source) else {
                throw DebugVideoCompressionError.staging
            }
            guard let read = await view.readStagedFile(staged.pending, from: staged.url) else {
                throw DebugVideoCompressionError.staging
            }
            view.settings.videoModel = "debug-video-model"
            let routed = await view.route(text: DropPrompt.text(pictures: 0, files: 0, videos: 1),
                                          pictures: [], files: [read])
            let routedBytes = routed?.turn.videos.first?.count ?? -1
            report.add("ANHANG", "datei=\(read.file) quelle=\(read.bytes) "
                       + "analyse=\(routedBytes) komprimiert=\(routedBytes > 0 && routedBytes < read.bytes) "
                       + "route=\(routed != nil)")
            if routed == nil { report.add("ROUTE", "kein turn") }

            documents.discardStored([stored.file, read.file])
            report.add("AUFRAEUMEN", "quelle=\(!FileManager.default.fileExists(atPath: stored.url.path)) "
                       + "cache=\(!FileManager.default.fileExists(atPath: cache.path)) "
                       + "angabe=\(!FileManager.default.fileExists(atPath: view.store.documents.storedURL(for: read.file)?.path ?? ""))")
        } catch {
            report.addFailure("FEHLER", error)
        }
    }

    nonisolated private static func size(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    nonisolated private static func makeVideo(in folder: URL) throws -> URL {
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
        guard writer.startWriting() else { throw DebugVideoCompressionError.writer }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<180 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let buffer = try pixelBuffer(from: adaptor, frame: frame)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            else { throw DebugVideoCompressionError.writer }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? DebugVideoCompressionError.writer }
        return url
    }

    nonisolated private static func pixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                    frame: Int) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw DebugVideoCompressionError.pool }
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
              let buffer = created else {
            throw DebugVideoCompressionError.pool
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw DebugVideoCompressionError.pool
        }
        var state = UInt32(truncatingIfNeeded: frame &+ 1)
        for index in 0..<CVPixelBufferGetDataSize(buffer) {
            state = state &* 1664525 &+ 1013904223
            base[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        return buffer
    }
}
#endif
#endif
