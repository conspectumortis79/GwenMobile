@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class VideoGenerationTests: GwenTestCase {
    private func mp4() -> Data {
        var data = Data([0, 0, 0, 0x18])
        data.append("ftypisom".data(using: .utf8)!)
        data.append(Data(repeating: 0, count: 24))
        return data
    }

    func testTheVideoRequestKeepsOnlyWhatTheUserNamed() {
        let request = VideoRequest.from(["prompt": "  Eine Katze im Regen  ", "duration": 30,
                                         "ratio": "9:16"])
        XCTAssertEqual(request?.prompt, "Eine Katze im Regen")
        XCTAssertEqual(request?.clampedDuration, 15)
        XCTAssertEqual(request?.ratio, .portrait)
        XCTAssertNil(VideoRequest.from([:]))
        XCTAssertNil(VideoRequest.from(["prompt": "   "]))
        XCTAssertEqual(VideoRequest.from(["prompt": "Wellen"])?.duration, VideoRequest.defaultDuration)
        XCTAssertEqual(VideoRequest.from(["prompt": "Wellen"])?.ratio, .landscape)
        XCTAssertEqual(VideoRequest.from(["prompt": "Wellen", "ratio": "7:3"])?.ratio, .landscape)
        XCTAssertEqual(VideoRequest.from(["prompt": "Wellen", "duration": 1])?.clampedDuration,
                       VideoRequest.minimumDuration)
    }

    func testVideoDetectionAndMimeType() {
        XCTAssertTrue(VideoBytes.isVideo(mp4()))
        XCTAssertFalse(VideoBytes.isVideo(Data("kein video".utf8)))
        XCTAssertEqual(VideoBytes.mimeType(mp4()), "video/mp4")
        var quickTime = Data([0, 0, 0, 0x18])
        quickTime.append("ftypqt  ".data(using: .utf8)!)
        quickTime.append(Data(repeating: 0, count: 8))
        XCTAssertEqual(VideoBytes.mimeType(quickTime), "video/quicktime")
        XCTAssertEqual(VideoBytes.mimeType(Data()), "video/mp4")
        var webm = Data([0x1A, 0x45, 0xDF, 0xA3])
        webm.append(Data(repeating: 0, count: 12))
        XCTAssertTrue(VideoBytes.isVideo(webm))
    }

    func testEveryRatioAndTheStepWordsAreStable() {
        XCTAssertEqual(Set(VideoRatio.allCases.map(\.size)).count, VideoRatio.allCases.count)
        let request = VideoRequest(prompt: "Wellen", duration: 20, ratio: .portrait)
        XCTAssertTrue(request.stepWords.contains("Wellen"))
        XCTAssertTrue(request.stepWords.contains("15s"))
        XCTAssertTrue(request.stepWords.contains("9:16"))
    }

    func testTheQwenBaseAndRequestBodyAreTheLegacyVideoProtocol() throws {
        let base = try QwenVideoAPI.base(fromChatBase: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(base, "https://dashscope-intl.aliyuncs.com/api/v1")
        XCTAssertThrowsError(try QwenVideoAPI.base(fromChatBase: "https://api.test/v1"))
        let body = QwenVideoAPI.body(model: "wan2.6-t2v",
                                     request: VideoRequest(prompt: "Wellen", duration: 8, ratio: .square))
        XCTAssertEqual(body["model"] as? String, "wan2.6-t2v")
        let input = body["input"] as? [String: Any]
        XCTAssertEqual(input?["prompt"] as? String, "Wellen")
        let parameters = body["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["size"] as? String, "960*960")
        XCTAssertEqual(parameters?["duration"] as? Int, 8)
        XCTAssertEqual(parameters?["prompt_extend"] as? Bool, true)
        let modern = QwenVideoAPI.body(model: "wan3.0-video",
                                       request: VideoRequest(prompt: "Wellen", duration: 8, ratio: .square))
        let modernParameters = try XCTUnwrap(modern["parameters"] as? [String: Any])
        XCTAssertEqual(modernParameters["resolution"] as? String, "720P")
        XCTAssertEqual(modernParameters["ratio"] as? String, "1:1")
        XCTAssertNil(modernParameters["size"])
        XCTAssertTrue(QwenVideoAPI.usesStructuredParameters("wan3.0-video"))
        XCTAssertTrue(QwenVideoAPI.usesStructuredParameters("wan2.7-t2v"))
        XCTAssertFalse(QwenVideoAPI.usesStructuredParameters("wan2.6-t2v"))
        XCTAssertTrue(QwenVideoAPI.usesStructuredParameters("some-video-model"))
        XCTAssertNil(QwenVideoAPI.wanVersion("some-video-model"))
    }

    func testTheTaskResponsesAreRead() throws {
        let created = Data(#"{"output":{"task_id":"task-1","task_status":"PENDING"}}"#.utf8)
        XCTAssertEqual(try QwenVideoAPI.taskID(from: created), "task-1")
        XCTAssertEqual(try QwenVideoAPI.state(from: Data(#"{"output":{"task_status":"RUNNING"}}"#.utf8)).phase,
                       .running)
        let ready = try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"SUCCEEDED","video_url":"https://video.test/a.mp4"}}"#.utf8))
        XCTAssertEqual(ready.phase, .succeeded(URL(string: "https://video.test/a.mp4")!))
        let failed = try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"FAILED","code":"Bad","message":"kaputt"}}"#.utf8))
        XCTAssertEqual(failed.phase, .failed("Bad: kaputt"))
        let emptyFailure = try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"FAILED"}}"#.utf8))
        XCTAssertEqual(emptyFailure.phase, .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"PENDING"}}"#.utf8)).phase, .pending)
        XCTAssertThrowsError(try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"SUCCEEDED"}}"#.utf8)))
        XCTAssertThrowsError(try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"SUCCEEDED","video_url":"http://video.test/a.mp4"}}"#.utf8)))
        XCTAssertThrowsError(try QwenVideoAPI.state(from: Data(
            #"{"output":{"task_status":"CANCELED"}}"#.utf8)))
    }

    func testTheQwenBackendCreatesPollsAndDownloads() async throws {
        let previous = QwenVideoAPI.pollInterval
        QwenVideoAPI.pollInterval = .milliseconds(1)
        defer { QwenVideoAPI.pollInterval = previous }
        let calls = LockedValue(0)
        let video = mp4()
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/video-synthesis") {
                return (200, Data(#"{"output":{"task_id":"task-1","task_status":"PENDING"}}"#.utf8))
            }
            if url.contains("/tasks/task-1") {
                let count = calls.mutate { value -> Int in
                    value += 1
                    return value
                }
                if count == 1 {
                    return (200, Data(#"{"output":{"task_status":"PENDING"}}"#.utf8))
                }
                if count == 2 {
                    return (200, Data(#"{"output":{"task_status":"RUNNING"}}"#.utf8))
                }
                return (200, Data(#"{"output":{"task_status":"SUCCEEDED","video_url":"https://video.test/a.mp4"}}"#.utf8))
            }
            if url.contains("/a.mp4") { return (200, video) }
            return (404, Data())
        }
        defer { MockHTTP.uninstall() }
        let generated = try await QwenVideoBackend().generate(
            baseURL: "https://api.test/compatible-mode/v1", key: "k", model: "wan2.6-t2v",
            request: VideoRequest(prompt: "Wellen", duration: 5))
        XCTAssertEqual(generated.data, video)
        XCTAssertEqual(calls.current, 3)
    }

    func testAVideoEditBodyUsesTheSourceAsReference() throws {
        let source = "data:video/mp4;base64,AAAA"
        let body = QwenVideoAPI.body(model: "wan3.0-video",
                                     request: VideoRequest(prompt: "Nur die Frau spricht", duration: 10),
                                     sourceURL: source)
        let input = try XCTUnwrap(body["input"] as? [String: Any])
        let media = try XCTUnwrap(input["media"] as? [[String: Any]])
        XCTAssertEqual(media.count, 1)
        XCTAssertEqual(media.first?["type"] as? String, "reference_video")
        XCTAssertEqual(media.first?["url"] as? String, source)
        let parameters = try XCTUnwrap(body["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["duration"] as? Int, 10)
        XCTAssertEqual(parameters["resolution"] as? String, "720P")
        XCTAssertEqual(parameters["prompt_extend"] as? Bool, false)
        XCTAssertNil(parameters["ratio"])
        XCTAssertNil(parameters["size"])
        let request = try QwenVideoAPI.createRequest(baseURL: "https://api.test/compatible-mode/v1",
                                                     key: "k", model: "wan3.0-video",
                                                     request: VideoRequest(prompt: "x"),
                                                     sourceURL: source)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-DashScope-Async"), "enable")
    }

    func testTheBackendSendsTheSourceAsBase64() async throws {
        let previous = QwenVideoAPI.pollInterval
        QwenVideoAPI.pollInterval = .milliseconds(1)
        defer { QwenVideoAPI.pollInterval = previous }
        let video = mp4()
        let captured = LockedValue<String?>(nil)
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/video-synthesis") {
                captured.set(MockHTTP.body(of: request))
                return (200, Data(#"{"output":{"task_id":"task-edit","task_status":"PENDING"}}"#.utf8))
            }
            if url.contains("/tasks/task-edit") {
                return (200, Data(#"{"output":{"task_status":"SUCCEEDED","video_url":"https://video.test/edit.mp4"}}"#.utf8))
            }
            if url.contains("/edit.mp4") { return (200, video) }
            return (404, Data())
        }
        defer { MockHTTP.uninstall() }
        let generated = try await QwenVideoBackend().generate(
            baseURL: "https://api.test/compatible-mode/v1", key: "k", model: "wan3.0-video",
            request: VideoRequest(prompt: "Nur die Frau spricht", duration: 10), sourceVideo: video)
        XCTAssertEqual(generated.data, video)
        let body = try XCTUnwrap(captured.current)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        let media = try XCTUnwrap(input["media"] as? [[String: Any]])
        XCTAssertEqual(media.first?["type"] as? String, "reference_video")
        XCTAssertTrue((media.first?["url"] as? String)?.hasPrefix("data:video/mp4;base64,") == true)
        XCTAssertEqual(input["prompt"] as? String, "Nur die Frau spricht")
        let parameters = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["duration"] as? Int, 10)
        XCTAssertEqual(parameters["prompt_extend"] as? Bool, false)
    }

    func testTheBackendTurnsAFailedTaskIntoAnError() async throws {
        let previous = QwenVideoAPI.pollInterval
        QwenVideoAPI.pollInterval = .milliseconds(1)
        defer { QwenVideoAPI.pollInterval = previous }
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/video-synthesis") {
                return (200, Data(#"{"output":{"task_id":"task-2","task_status":"PENDING"}}"#.utf8))
            }
            return (200, Data(#"{"output":{"task_status":"FAILED","code":"Bad","message":"kaputt"}}"#.utf8))
        }
        defer { MockHTTP.uninstall() }
        do {
            _ = try await QwenVideoBackend().generate(
                baseURL: "https://api.test/compatible-mode/v1", key: "k", model: "wan2.6-t2v",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kaputt"))
        }
    }

    func testTheBackendStopsAfterItsPollingBudget() async throws {
        let previous = QwenVideoAPI.pollInterval
        QwenVideoAPI.pollInterval = .milliseconds(1)
        defer { QwenVideoAPI.pollInterval = previous }
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/video-synthesis") {
                return (200, Data(#"{"output":{"task_id":"task-3","task_status":"PENDING"}}"#.utf8))
            }
            return (200, Data(#"{"output":{"task_status":"RUNNING"}}"#.utf8))
        }
        defer { MockHTTP.uninstall() }
        do {
            _ = try await QwenVideoBackend().generate(
                baseURL: "https://api.test/compatible-mode/v1", key: "k", model: "wan2.6-t2v",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_timeout"))
        }
    }

    func testTheDownloadRejectsATextResponseAndAnHTTPFailure() async throws {
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            _ = try await QwenVideoAPI.download(URL(string: "https://video.test/a.mp4")!)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.install { _ in (200, Data("kein video".utf8)) }
        do {
            _ = try await QwenVideoAPI.download(URL(string: "https://video.test/a.mp4")!)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_download_failed"))
        }
        MockHTTP.uninstall()
    }

    func testTheChatRequestCarriesAVideoPart() throws {
        let data = mp4()
        let message = ChatMessage(role: .user, text: "Was passiert hier?")
        let request = try QwenAPI.makeRequest(baseURL: "https://api.test/v1", key: "k", model: "qwen3.8-max",
                                              messages: [message], imageData: [], videoData: [data],
                                              stream: false, thinking: .nothing)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(user["content"] as? [[String: Any]])
        XCTAssertTrue(content.contains { $0["type"] as? String == "video_url" })
        XCTAssertTrue(content.contains { $0["type"] as? String == "text" })
        let video = try XCTUnwrap(content.first { $0["type"] as? String == "video_url" })
        let url = try XCTUnwrap(video["video_url"] as? [String: Any])
        XCTAssertTrue((url["url"] as? String)?.hasPrefix("data:video/mp4;base64,") == true)
    }

    func testAVideoOnlyMessageGetsTheFallbackQuestion() throws {
        let message = ChatMessage(role: .user, text: "")
        let request = try QwenAPI.makeRequest(baseURL: "https://api.test/v1", key: "k", model: "qwen3.8-max",
                                              messages: [message], imageData: [], videoData: [mp4()],
                                              stream: false, thinking: .nothing)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, L.t("describe_video"))
    }

    func testAnEmptyTaskIDIsRejected() {
        XCTAssertThrowsError(try QwenVideoAPI.taskID(from: Data(#"{"output":{"task_id":"","task_status":"PENDING"}}"#.utf8)))
    }
}
