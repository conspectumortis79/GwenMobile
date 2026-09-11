import Foundation
import AVFoundation

@MainActor
final class VoiceTranscriber: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State { case idle, recording, processing }

    static let maxSeconds = 28
    static let minPCMLength = 3200
    static let sendChunkSize = 3200
    static let transcriptTimeout: TimeInterval = 15

    @Published var state: State = .idle
    @Published var lastError: L.FriendlyError?
    @Published var remaining: Int?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var job: (baseURL: String, key: String, model: String, onText: @MainActor (String) -> Void)?
    private var ticker: Task<Void, Never>?

    func start(baseURL: String, key: String, model: String,
               onText: @escaping @MainActor (String) -> Void) {
        guard state == .idle else { return }
        if AVAudioApplication.shared.recordPermission != .granted {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted { self.start(baseURL: baseURL, key: key, model: model, onText: onText) }
                    else { self.lastError = L.FriendlyError(message: L.t("mic_denied"), detail: "", openSettings: false) }
                }
            }
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            lastError = L.friendlyError(error.localizedDescription)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(UUID().uuidString.prefix(8)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: WAVCodec.targetSampleRate,
            AVNumberOfChannelsKey: WAVCodec.targetChannels,
            AVLinearPCMBitDepthKey: WAVCodec.targetBitsPerSample,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            guard r.prepareToRecord(), r.record(forDuration: TimeInterval(Self.maxSeconds)) else {
                lastError = L.FriendlyError(message: L.t("mic_denied"), detail: "", openSettings: false)
                return
            }
            recorder = r
            fileURL = url
            job = (baseURL, key, model, onText)
            state = .recording
            remaining = Self.maxSeconds
            let end = Date().addingTimeInterval(TimeInterval(Self.maxSeconds))
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.state == .recording else { break }
                    let left = Int(ceil(end.timeIntervalSinceNow))
                    self.remaining = left > 0 ? left : nil
                    if left <= 0 { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        } catch {
            lastError = L.friendlyError(error.localizedDescription)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard state == .recording, let job else { return }
            stopAndTranscribe(baseURL: job.baseURL, key: job.key,
                              model: job.model, onText: job.onText)
        }
    }

    func stopAndTranscribe(baseURL: String, key: String, model: String,
                           onText: @escaping @MainActor (String) -> Void) {
        guard state == .recording, let rec = recorder, let url = fileURL else { return }
        state = .processing
        recorder = nil
        job = nil
        ticker?.cancel()
        ticker = nil
        remaining = nil
        rec.stop()
        Task {
            defer { state = .idle }
            do {
                let wav = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                let pcm = WAVCodec.pcm(fromWAV: wav)
                guard pcm.count > Self.minPCMLength else {
                    lastError = L.FriendlyError(message: L.t("asr_empty"), detail: "", openSettings: false)
                    return
                }
                let text = try await Self.transcribe(pcm: pcm, baseURL: baseURL, key: key, model: model)
                guard !text.isEmpty else {
                    lastError = L.FriendlyError(message: L.t("asr_empty"), detail: "", openSettings: false)
                    return
                }
                onText(text)
            } catch {
                lastError = L.friendlyError(error.localizedDescription)
            }
        }
    }

    static func transcribe(pcm: Data, baseURL: String, key: String, model: String) async throws -> String {
        let client = try await RealtimeClient.opened(baseURL: baseURL, model: model, key: key,
                                                     timeoutMessage: L.t("asr_timeout"),
                                                     fallbackError: "WebSocket error")
        defer { client.close() }
        try await client.startSession([
            "modalities": ["text"],
            "input_audio_format": "pcm",
            "input_audio_transcription": [
                "model": model,
                "language": L.lang == .de ? "de" : "en",
            ],
            "turn_detection": NSNull(),
        ])
        var idx = pcm.startIndex
        while idx < pcm.endIndex {
            let end = min(idx + sendChunkSize, pcm.endIndex)
            try await client.send(["type": "input_audio_buffer.append",
                                   "audio": pcm.subdata(in: idx..<end).base64EncodedString()])
            idx = end
        }
        try await client.send(["type": "input_audio_buffer.commit"])
        try await client.send(["type": "response.create"])

        let deadline = Date().addingTimeInterval(transcriptTimeout)
        while Date() < deadline {
            let ev = try await client.receive(until: deadline)
            if ev.type == "conversation.item.input_audio_transcription.completed" {
                return ev.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if ev.type == RealtimeClient.errorType {
                throw APIError(message: ev.errorMessage ?? "WebSocket error")
            }
        }
        throw APIError(message: L.t("asr_timeout"))
    }
}
