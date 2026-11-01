import GwenMobileKit
import Foundation

struct LocalDownloadFile: Equatable, Sendable {
    var path: String
    var bytes: Int64
    var url: URL
}

struct LocalDownloadPlan: Equatable, Sendable {
    var files: [LocalDownloadFile]
    var totalBytes: Int64
}

enum LocalDownloadError: LocalizedError {
    case http(Int)
    case emptyPlan
    case noWeights
    case noSpace(needed: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .emptyPlan: return L.t("local_download_empty")
        case .noWeights: return L.t("local_download_no_weights")
        case .noSpace(let needed, let available):
            return L.fmt2("local_download_no_space", StorageUsage.bytesText(Int(clamping: needed)),
                          StorageUsage.bytesText(Int(clamping: available)))
        }
    }
}

struct LocalModelDownloader: Sendable {
    let files: LocalModelFiles
    let session: URLSession

    init(files: LocalModelFiles = LocalModelFiles(), session: URLSession = LocalModelDownloader.makeSession()) {
        self.files = files
        self.session = session
    }

    static func makeSession() -> URLSession {
        LocalURLSession.ephemeral(requestTimeout: 120, resourceTimeout: 3600, connectionsPerHost: 1)
    }

    func install(_ choice: LocalModelChoice,
                 progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> LocalModelManifest {
        try Task.checkCancellation()
        let plan = try await plan(for: choice)
        let needed = plan.totalBytes
        let available = availableBytes(at: files.root)
        guard needed <= available else {
            throw LocalDownloadError.noSpace(needed: needed, available: available)
        }
        let partial = files.partialDirectory(for: choice.id)
        let manager = FileManager.default
        try? manager.removeItem(at: partial)
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        progress(0, plan.totalBytes)
        var done: Int64 = 0
        do {
            for file in plan.files {
                try Task.checkCancellation()
                let target = partial.appendingPathComponent(file.path)
                try manager.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                let completed = done
                try await download(file, to: target) { written, expected in
                    let span = expected > 0 ? expected : max(file.bytes, 1)
                    let fraction = min(1, max(0, Double(written) / Double(span)))
                    let current = Int64(Double(span) * fraction)
                    progress(min(plan.totalBytes, completed + current), plan.totalBytes)
                }
                done += max(file.bytes, 0)
                progress(min(plan.totalBytes, done), plan.totalBytes)
            }
            let final = files.directory(for: choice.id)
            try? manager.removeItem(at: final)
            try manager.createDirectory(at: files.root, withIntermediateDirectories: true)
            try manager.moveItem(at: partial, to: final)
            let manifest = LocalModelManifest(repo: choice.id,
                                              bytes: plan.totalBytes,
                                              name: choice.name,
                                              family: choice.family,
                                              context: choice.context,
                                              vision: choice.vision,
                                              tools: choice.tools,
                                              parameterBillions: choice.parameterBillions,
                                              quantization: choice.quantization,
                                              source: choice.source)
            try files.write(manifest, for: choice.id)
            progress(plan.totalBytes, plan.totalBytes)
            return manifest
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    func plan(for choice: LocalModelChoice) async throws -> LocalDownloadPlan {
        let chosen = try await remoteFiles(for: choice.id)
        guard !chosen.isEmpty else { throw LocalDownloadError.emptyPlan }
        guard chosen.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw LocalDownloadError.noWeights
        }
        let total = chosen.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
        return LocalDownloadPlan(files: chosen, totalBytes: total > 0 ? total : choice.bytes)
    }

    func download(_ file: LocalDownloadFile, to target: URL,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let transfer = LocalFileTransfer(destination: target, progress: progress)
        try await withTaskCancellationHandler {
            try await transfer.start(url: file.url, session: session)
        } onCancel: {
            transfer.cancel()
        }
    }

    private struct RemoteInfo: Decodable {
        var siblings: [RemoteSibling]

        struct RemoteSibling: Decodable {
            var rfilename: String
            var size: Int64?
        }
    }

    private func remoteFiles(for repo: String) async throws -> [LocalDownloadFile] {
        guard let url = HuggingFaceHub.detailURL(for: repo) else {
            throw LocalDownloadError.emptyPlan
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("GwenMobile", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await HTTP.data(request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code < 400 else { throw LocalDownloadError.http(code) }
        let info = try await Offload.run { try JSONDecoder().decode(RemoteInfo.self, from: data) }
        return info.siblings.compactMap { sibling in
            let path = sibling.rfilename
            guard HuggingFaceHub.isModelFile(path), let fileURL = HuggingFaceHub.fileURL(repo: repo, path: path)
            else { return nil }
            return LocalDownloadFile(path: path, bytes: sibling.size ?? 0, url: fileURL)
        }
    }

    private func availableBytes(at url: URL) -> Int64 {
        let manager = FileManager.default
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        let attributes = try? manager.attributesOfFileSystem(forPath: url.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}

final class LocalFileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var moveError: Error?

    init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(url: URL, session: URLSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            let delegateSession = URLSession(configuration: session.configuration, delegate: self,
                                             delegateQueue: nil)
            lock.lock()
            self.session = delegateSession
            let download = delegateSession.downloadTask(with: url)
            self.task = download
            lock.unlock()
            download.resume()
        }
    }

    func cancel() {
        lock.lock()
        let download = task
        lock.unlock()
        download?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        guard status < 400 else {
            moveError = LocalDownloadError.http(status)
            return
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let failure = error ?? moveError
        finish(failure)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        let activeSession = session
        session = nil
        task = nil
        lock.unlock()
        activeSession?.finishTasksAndInvalidate()
        guard let waiting else { return }
        if let error {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                waiting.resume(throwing: CancellationError())
            } else {
                waiting.resume(throwing: error)
            }
        } else {
            waiting.resume()
        }
    }
}
