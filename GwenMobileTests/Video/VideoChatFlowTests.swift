@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class VideoChatFlowTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        QwenVideoAPI.pollInterval = .milliseconds(1)
    }

    override func tearDown() async throws {
        QwenVideoAPI.pollInterval = .seconds(15)
        MockHTTP.uninstall()
        hosted.close()
        try await super.tearDown()
    }

    private func mp4() -> Data {
        var data = Data([0, 0, 0, 0x18])
        data.append("ftypisom".data(using: .utf8)!)
        data.append(Data(repeating: 0, count: 24))
        return data
    }

    func testAnAttachedVideoIsSentAsTheReferenceOfTheEdit() async throws {
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
        let paths = temporaryPaths("video-edit-chat")
        let store = HostedChatView.store(paths)
        let savedProvider = AppSettings.shared.provider
        let savedProfile = AppSettings.shared.profile
        let savedQwenProfile = AppSettings.shared.profile(of: .qwenCloud)
        let savedKey = AppSettings.shared.key(for: .qwenCloud)
        defer {
            AppSettings.shared.provider = savedProvider
            AppSettings.shared.profiles[savedProvider] = savedProfile
            AppSettings.shared.profiles[.qwenCloud] = savedQwenProfile
            AppSettings.shared.setKey(savedKey, for: .qwenCloud)
        }
        AppSettings.shared.provider = .qwenCloud
        AppSettings.shared.setKey("video-test-key", for: .qwenCloud)
        AppSettings.shared.videoGenerationModel = "test-video-model"
        let view = try await hosted.open(store, in: self)
        let convID = try XCTUnwrap(store.current?.id)
        await view.runVideoFlow(VideoRequest(prompt: "Nur die Frau spricht", duration: 10),
                                sourceVideo: video, convID: convID, started: Date())
        let answer = try XCTUnwrap(store.current?.messages.last)
        XCTAssertEqual(answer.text, L.t("video_done_note"))
        let body = try XCTUnwrap(captured.current)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        let media = try XCTUnwrap(input["media"] as? [[String: Any]])
        XCTAssertEqual(media.first?["type"] as? String, "reference_video")
        XCTAssertTrue((media.first?["url"] as? String)?.hasPrefix("data:video/mp4;base64,") == true)
    }

    func testTheGeneratedVideoIsStoredAndShownInTheChat() async throws {
        let video = mp4()
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/video-synthesis") {
                return (200, Data(#"{"output":{"task_id":"task-1","task_status":"PENDING"}}"#.utf8))
            }
            if url.contains("/tasks/task-1") {
                return (200, Data(#"{"output":{"task_status":"SUCCEEDED","video_url":"https://video.test/a.mp4"}}"#.utf8))
            }
            if url.contains("/a.mp4") { return (200, video) }
            return (200, MockHTTP.completion("ok"))
        }
        let paths = temporaryPaths("video-chat")
        let store = HostedChatView.store(paths)
        let savedProvider = AppSettings.shared.provider
        let savedProfile = AppSettings.shared.profile
        let savedQwenProfile = AppSettings.shared.profile(of: .qwenCloud)
        let savedKey = AppSettings.shared.key(for: .qwenCloud)
        defer {
            AppSettings.shared.provider = savedProvider
            AppSettings.shared.profiles[savedProvider] = savedProfile
            AppSettings.shared.profiles[.qwenCloud] = savedQwenProfile
            AppSettings.shared.setKey(savedKey, for: .qwenCloud)
        }
        AppSettings.shared.provider = .qwenCloud
        AppSettings.shared.setKey("video-test-key", for: .qwenCloud)
        AppSettings.shared.videoGenerationModel = "test-video-model"
        let view = try await hosted.open(store, in: self)
        let convID = try XCTUnwrap(store.current?.id)
        await view.runVideoFlow(VideoRequest(prompt: "Wellen am Strand", duration: 5),
                                convID: convID, started: Date())
        let answer = try XCTUnwrap(store.current?.messages.last)
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertEqual(answer.text, L.t("video_done_note"))
        let file = try XCTUnwrap(answer.files.first)
        XCTAssertEqual(file.kind, .video)
        XCTAssertEqual(file.bytes, video.count)
        let url = try XCTUnwrap(store.documents.storedURL(for: file.file))
        XCTAssertEqual(try Data(contentsOf: url), video)
    }
}
