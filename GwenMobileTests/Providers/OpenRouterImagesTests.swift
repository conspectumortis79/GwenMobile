@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class OpenRouterImagesTests: XCTestCase {
    private let base = "https://openrouter.ai/api/v1"

    func testGenerationRequestCarriesModelPromptAndOneImage() throws {
        let request = try OpenRouterImageAPI.request(baseURL: base, key: "k", model: "google/gemini-2.5-flash-image",
                                                     prompt: "Eine rote Tasse", inputImages: [], isEdit: false)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/images")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let body = jsonBody(of: request)
        XCTAssertEqual(body?["model"] as? String, "google/gemini-2.5-flash-image")
        XCTAssertEqual(body?["prompt"] as? String, "Eine rote Tasse")
        XCTAssertEqual(body?["n"] as? Int, 1)
        XCTAssertNil(body?["input_references"])
    }

    func testEditingSendsReferenceImagesAsDataURLsWithTheEditFrame() throws {
        L.apply(.de)
        let picture = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let request = try OpenRouterImageAPI.request(baseURL: base, key: "k", model: "openai/gpt-image-1",
                                                     prompt: "mach die Tasse blau", inputImages: [picture], isEdit: true)
        let body = jsonBody(of: request)
        let references = body?["input_references"] as? [[String: Any]]
        XCTAssertEqual(references?.count, 1)
        XCTAssertEqual(references?.first?["type"] as? String, "image_url")
        let url = (references?.first?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url, try XCTUnwrap(QwenAPI.dataURL(picture)))
        let prompt = body?["prompt"] as? String ?? ""
        XCTAssertTrue(prompt.contains("mach die Tasse blau"))
        XCTAssertTrue(prompt.hasPrefix(L.fmt("edit_frame", "").trimmingCharacters(in: .whitespaces).prefix(20)))
    }

    func testPicturesAreDecodedFromBase64AndEmptyAnswersFail() throws {
        let bytes = Data([1, 2, 3, 4])
        let payload = #"{"created":1,"data":[{"b64_json":"\#(bytes.base64EncodedString())","media_type":"image/png"}],"usage":{"cost":0.01}}"#
        XCTAssertEqual(try OpenRouterImageAPI.pictures(from: Data(payload.utf8)), [bytes])
        XCTAssertThrowsError(try OpenRouterImageAPI.pictures(from: Data(#"{"data":[]}"#.utf8)))
        XCTAssertThrowsError(try OpenRouterImageAPI.pictures(from: Data(#"{"data":[{"url":"https://x"}]}"#.utf8)))
    }

    func testImageModelListIsSortedAndTargetsTheImageModelsEndpoint() throws {
        let request = try OpenRouterImageAPI.imageModelsRequest(baseURL: base, key: "k")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/images/models")
        let payload = #"{"data":[{"id":"openai/gpt-image-1","architecture":{"input_modalities":["text","image"]}},{"id":"google/gemini-2.5-flash-image"}]}"#
        XCTAssertEqual(try OpenRouterImageAPI.imageModels(from: Data(payload.utf8)),
                       ["google/gemini-2.5-flash-image", "openai/gpt-image-1"])
    }

    func testProfilesWithoutImageModelsFallBackToTheNameFilterUntilReloaded() throws {
        let legacy = Data(#"{"chatModel":"a","visionModel":"b","imageModel":"","chatThinkingLevel":"default","availableModels":["x/chat","x/gpt-image-1","wan2.7-image"],"modelCaps":{}}"#.utf8)
        let profile = try JSONDecoder().decode(ProviderProfile.self, from: legacy)
        XCTAssertEqual(profile.imageCandidates, ["x/gpt-image-1", "wan2.7-image"])
        XCTAssertTrue(profile.needsListing)
        var fresh = profile
        fresh.adopt(ModelListingResult(models: ["x/chat"], imageModels: ["seedream/4.5"]))
        XCTAssertEqual(fresh.imageCandidates, ["seedream/4.5"])
        XCTAssertEqual(fresh.imageModel, "seedream/4.5")
        XCTAssertFalse(fresh.needsListing)
        XCTAssertTrue(ProviderProfile().needsListing)
        let back = try JSONDecoder().decode(ProviderProfile.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(back, fresh)
    }

    func testDashScopeBackendKeepsTheWanFrameAndTheEditWrapper() {
        L.apply(.de)
        XCTAssertEqual(ImagePromptFrame.framed("p", inputImages: 0, isEdit: true), "p")
        XCTAssertEqual(ImagePromptFrame.framed("p", inputImages: 1, isEdit: false), "p")
        XCTAssertEqual(ImagePromptFrame.framed("p", inputImages: 1, isEdit: true), L.fmt("edit_frame", "p"))
        XCTAssertEqual(ImagePromptFrame.framed("p", inputImages: 2, isEdit: true), L.fmt("edit_frame_multi", "p"))
    }
}
