@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class RemoteVideoGenerationTests: GwenTestCase {
    private func mp4() -> Data {
        var data = Data([0, 0, 0, 0x18])
        data.append("ftypisom".data(using: .utf8)!)
        data.append(Data(repeating: 0, count: 24))
        return data
    }

    override func tearDown() async throws {
        OpenRouterVideoAPI.pollInterval = .seconds(10)
        OpenAIVideoAPI.pollInterval = .seconds(10)
        MockHTTP.uninstall()
        try await super.tearDown()
    }

    func testOpenRouterModelListerUsesTheVideoEndpoint() async throws {
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") {
                return (200, Data(#"{"data":[{"id":"google/veo-3.1"},{"id":"bytedance/seedance-2.5"}]}"#.utf8))
            }
            if url.contains("/images/models") {
                return (200, Data(#"{"data":[{"id":"x/image"}]}"#.utf8))
            }
            if url.contains("/models") {
                return (200, Data(#"{"data":[{"id":"chat"}]}"#.utf8))
            }
            return (404, Data())
        }
        let result = try await OpenRouterModelLister().list(baseURL: "https://or.test/api/v1", key: "k")
        XCTAssertEqual(result.models, ["chat"])
        XCTAssertEqual(result.imageModels, ["x/image"])
        XCTAssertEqual(result.videoGenerationModels, ["bytedance/seedance-2.5", "google/veo-3.1"])
    }

    func testOpenRouterModelListerFallsBackToTheNameFilter() async throws {
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") { return (500, Data()) }
            if url.contains("/images/models") { return (500, Data()) }
            return (200, Data(#"{"data":[{"id":"some-video-model"},{"id":"chat"}]}"#.utf8))
        }
        let result = try await OpenRouterModelLister().list(baseURL: "https://or.test/api/v1", key: "k")
        XCTAssertEqual(result.videoGenerationModels, ["some-video-model"])
    }

    func testOpenRouterVideoBodyAndSourceReference() {
        let source = mp4()
        let request = VideoRequest(prompt: "Wellen", duration: 8, ratio: .portrait)
        let withSource = OpenRouterVideoAPI.body(model: "bytedance/seedance-2.5", request: request,
                                                 sourceVideo: source)
        XCTAssertEqual(withSource["model"] as? String, "bytedance/seedance-2.5")
        XCTAssertEqual(withSource["prompt"] as? String, "Wellen")
        XCTAssertEqual(withSource["duration"] as? Int, 8)
        XCTAssertEqual(withSource["aspect_ratio"] as? String, "9:16")
        XCTAssertEqual(withSource["resolution"] as? String, "720p")
        let references = withSource["input_references"] as? [[String: Any]]
        XCTAssertEqual(references?.count, 1)
        XCTAssertEqual(references?.first?["type"] as? String, "video_url")
        let videoURL = (references?.first?["video_url"] as? [String: Any])?["url"] as? String
        XCTAssertTrue(videoURL?.hasPrefix("data:video/mp4;base64,") == true)
        let withoutSource = OpenRouterVideoAPI.body(model: "bytedance/seedance-2.5", request: request,
                                                    sourceVideo: nil)
        XCTAssertNil(withoutSource["input_references"])
        XCTAssertEqual(OpenRouterVideoAPI.dataURL(source), videoURL)
    }

    func testOpenRouterVideoJobResponsesAreRead() throws {
        let created = Data(#"{"id":"job-1","status":"pending","polling_url":"/api/v1/videos/job-1"}"#.utf8)
        XCTAssertEqual(try OpenRouterVideoAPI.jobID(from: created), "job-1")
        XCTAssertThrowsError(try OpenRouterVideoAPI.jobID(from: Data(#"{"id":""}"#.utf8)))
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"pending"}"#.utf8)),
                       .pending)
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"in_progress"}"#.utf8)),
                       .running)
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"running"}"#.utf8)),
                       .running)
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"completed"}"#.utf8)),
                       .succeeded)
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"succeeded"}"#.utf8)),
                       .succeeded)
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(
            #"{"id":"j","status":"failed","error":"kaputt"}"#.utf8)), .failed("kaputt"))
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"failed"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"cancelled"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"canceled"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"expired"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertThrowsError(try OpenRouterVideoAPI.phase(from: Data(#"{"id":"j","status":"odd"}"#.utf8)))
    }

    func testOpenRouterVideoBackendCreatesPollsAndDownloads() async throws {
        OpenRouterVideoAPI.pollInterval = .milliseconds(1)
        let video = mp4()
        let calls = LockedValue(0)
        let captured = LockedValue<String?>(nil)
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                captured.set(MockHTTP.body(of: request))
                return (202, Data(#"{"id":"job-1","status":"pending"}"#.utf8))
            }
            if url.contains("/videos/job-1/content") { return (200, video) }
            if url.contains("/videos/job-1") {
                let count = calls.mutate { value -> Int in
                    value += 1
                    return value
                }
                if count == 1 {
                    return (200, Data(#"{"id":"job-1","status":"pending"}"#.utf8))
                }
                if count == 2 {
                    return (200, Data(#"{"id":"job-1","status":"in_progress"}"#.utf8))
                }
                return (200, Data(#"{"id":"job-1","status":"completed"}"#.utf8))
            }
            return (404, Data())
        }
        let generated = try await OpenRouterVideoBackend().generate(
            baseURL: "https://or.test/api/v1", key: "k", model: "bytedance/seedance-2.5",
            request: VideoRequest(prompt: "Wellen", duration: 8), sourceVideo: video)
        XCTAssertEqual(generated.data, video)
        XCTAssertEqual(calls.current, 3)
        let body = try XCTUnwrap(captured.current)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "bytedance/seedance-2.5")
        XCTAssertEqual(object["prompt"] as? String, "Wellen")
        XCTAssertNotNil(object["input_references"])
    }

    func testOpenRouterVideoBackendTurnsFailuresAndTimeoutsIntoErrors() async throws {
        OpenRouterVideoAPI.pollInterval = .milliseconds(1)
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                return (202, Data(#"{"id":"job-2","status":"pending"}"#.utf8))
            }
            return (200, Data(#"{"id":"job-2","status":"failed","error":"kaputt"}"#.utf8))
        }
        do {
            _ = try await OpenRouterVideoBackend().generate(
                baseURL: "https://or.test/api/v1", key: "k", model: "google/veo-3.1",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kaputt"))
        }
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                return (202, Data(#"{"id":"job-3","status":"pending"}"#.utf8))
            }
            return (200, Data(#"{"id":"job-3","status":"running"}"#.utf8))
        }
        do {
            _ = try await OpenRouterVideoBackend().generate(
                baseURL: "https://or.test/api/v1", key: "k", model: "google/veo-3.1",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_timeout"))
        }
    }

    func testOpenRouterVideoDownloadRejectsTextAndHTTPFailures() async throws {
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            _ = try await OpenRouterVideoAPI.download(baseURL: "https://or.test/api/v1", key: "k", id: "job-1")
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.install { _ in (200, Data("kein video".utf8)) }
        do {
            _ = try await OpenRouterVideoAPI.download(baseURL: "https://or.test/api/v1", key: "k", id: "job-1")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_download_failed"))
        }
    }

    func testOpenAIVideoBodyUsesOpenAIShape() {
        let body = OpenAIVideoAPI.body(model: "sora-2",
                                       request: VideoRequest(prompt: "Wellen", duration: 2,
                                                             ratio: .landscape))
        XCTAssertEqual(body["model"] as? String, "sora-2")
        XCTAssertEqual(body["prompt"] as? String, "Wellen")
        XCTAssertEqual(body["seconds"] as? String, "4")
        XCTAssertEqual(body["size"] as? String, "1280x720")
        for duration in [5, 6, 7, 8, 10, 11, 15] {
            let value = OpenAIVideoAPI.seconds(duration)
            XCTAssertTrue(["4", "8", "12"].contains(value))
        }
        XCTAssertEqual(OpenAIVideoAPI.seconds(5), "4")
        XCTAssertEqual(OpenAIVideoAPI.seconds(6), "4")
        XCTAssertEqual(OpenAIVideoAPI.seconds(7), "8")
        XCTAssertEqual(OpenAIVideoAPI.seconds(8), "8")
        XCTAssertEqual(OpenAIVideoAPI.seconds(10), "8")
        XCTAssertEqual(OpenAIVideoAPI.seconds(11), "12")
        XCTAssertEqual(OpenAIVideoAPI.seconds(15), "12")
        XCTAssertEqual(OpenAIVideoAPI.size(.landscape), "1280x720")
        XCTAssertEqual(OpenAIVideoAPI.size(.square), "1280x720")
        XCTAssertEqual(OpenAIVideoAPI.size(.fourThree), "1280x720")
        XCTAssertEqual(OpenAIVideoAPI.size(.portrait), "720x1280")
        XCTAssertEqual(OpenAIVideoAPI.size(.threeFour), "720x1280")
    }

    func testOpenAICompatibleVideoJobResponsesAreRead() throws {
        let created = Data(#"{"id":"video-1","status":"queued"}"#.utf8)
        XCTAssertEqual(try OpenAIVideoAPI.jobID(from: created), "video-1")
        XCTAssertThrowsError(try OpenAIVideoAPI.jobID(from: Data(#"{"id":""}"#.utf8)))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"queued"}"#.utf8)),
                       .pending)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"pending"}"#.utf8)),
                       .pending)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"in_progress"}"#.utf8)),
                       .running)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"running"}"#.utf8)),
                       .running)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"completed"}"#.utf8)),
                       .succeeded)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"succeeded"}"#.utf8)),
                       .succeeded)
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(
            #"{"id":"v","status":"failed","error":{"message":"kaputt"}}"#.utf8)), .failed("kaputt"))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(
            #"{"id":"v","status":"failed","error":{}}"#.utf8)), .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"failed"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"cancelled"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"canceled"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertEqual(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"expired"}"#.utf8)),
                       .failed(L.t("video_generation_failed")))
        XCTAssertThrowsError(try OpenAIVideoAPI.phase(from: Data(#"{"id":"v","status":"odd"}"#.utf8)))
    }

    func testOpenAICompatibleModelListerUsesTheVideoEndpoint() async throws {
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") {
                return (200, Data(#"{"data":[{"id":"sora-2"}]}"#.utf8))
            }
            return (200, Data(#"{"data":[{"id":"chat"}]}"#.utf8))
        }
        let result = try await OpenAICompatibleModelLister().list(baseURL: "https://ai.test/v1", key: "k")
        XCTAssertEqual(result.models, ["chat"])
        XCTAssertEqual(result.videoGenerationModels, ["sora-2"])
    }

    func testOpenAICompatibleModelListerFallsBackToNames() async throws {
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") { return (404, Data()) }
            return (200, Data(#"{"data":[{"id":"some-video-model"},{"id":"chat"}]}"#.utf8))
        }
        let result = try await OpenAICompatibleModelLister().list(baseURL: "https://ai.test/v1", key: "k")
        XCTAssertEqual(result.videoGenerationModels, ["some-video-model"])
    }

    func testOpenAICompatibleVideoBackendCreatesPollsAndDownloads() async throws {
        OpenAIVideoAPI.pollInterval = .milliseconds(1)
        let video = mp4()
        let calls = LockedValue(0)
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                return (200, Data(#"{"id":"video-1","status":"queued"}"#.utf8))
            }
            if url.contains("/videos/video-1/content") { return (200, video) }
            if url.contains("/videos/video-1") {
                let count = calls.mutate { value -> Int in
                    value += 1
                    return value
                }
                if count == 1 {
                    return (200, Data(#"{"id":"video-1","status":"queued"}"#.utf8))
                }
                if count == 2 {
                    return (200, Data(#"{"id":"video-1","status":"in_progress"}"#.utf8))
                }
                return (200, Data(#"{"id":"video-1","status":"completed"}"#.utf8))
            }
            return (404, Data())
        }
        let generated = try await OpenAIVideoBackend().generate(
            baseURL: "https://ai.test/v1", key: "k", model: "sora-2",
            request: VideoRequest(prompt: "Wellen", duration: 8))
        XCTAssertEqual(generated.data, video)
        XCTAssertEqual(calls.current, 3)
    }

    func testOpenAICompatibleVideoBackendRejectsSourceVideo() async {
        do {
            _ = try await OpenAIVideoBackend().generate(
                baseURL: "https://ai.test/v1", key: "k", model: "sora-2",
                request: VideoRequest(prompt: "Wellen"), sourceVideo: mp4())
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_edit_unsupported"))
        }
    }

    func testOpenAICompatibleVideoBackendTurnsFailuresAndTimeoutsIntoErrors() async throws {
        OpenAIVideoAPI.pollInterval = .milliseconds(1)
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                return (200, Data(#"{"id":"video-2","status":"queued"}"#.utf8))
            }
            return (200, Data(#"{"id":"video-2","status":"failed","error":{"message":"kaputt"}}"#.utf8))
        }
        do {
            _ = try await OpenAIVideoBackend().generate(
                baseURL: "https://ai.test/v1", key: "k", model: "sora-2",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kaputt"))
        }
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/videos") && request.httpMethod == "POST" {
                return (200, Data(#"{"id":"video-3","status":"queued"}"#.utf8))
            }
            return (200, Data(#"{"id":"video-3","status":"in_progress"}"#.utf8))
        }
        do {
            _ = try await OpenAIVideoBackend().generate(
                baseURL: "https://ai.test/v1", key: "k", model: "sora-2",
                request: VideoRequest(prompt: "Wellen"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_timeout"))
        }
    }

    func testOpenAICompatibleVideoDownloadRejectsTextAndHTTPFailures() async throws {
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            _ = try await OpenAIVideoAPI.download(baseURL: "https://ai.test/v1", key: "k", id: "video-1")
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.install { _ in (200, Data("kein video".utf8)) }
        do {
            _ = try await OpenAIVideoAPI.download(baseURL: "https://ai.test/v1", key: "k", id: "video-1")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("video_download_failed"))
        }
    }

    func testRemoteDescriptorsAdvertiseTheirVideoBackends() {
        let router = OpenRouterDescriptor()
        XCTAssertEqual(router.capabilities[.videoGeneration], .available)
        XCTAssertNotNil(router.videoGenerationBackend)
        let compatible = OpenAICompatibleDescriptor()
        XCTAssertEqual(compatible.capabilities[.videoGeneration], .probed)
        XCTAssertNotNil(compatible.videoGenerationBackend)
        XCTAssertTrue(compatible.modelLister is OpenAICompatibleModelLister)
    }
}
