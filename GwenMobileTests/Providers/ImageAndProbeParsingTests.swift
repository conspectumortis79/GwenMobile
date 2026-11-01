@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ImageAndProbeParsingTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testTheOpenRouterImageRequestAndParsing() throws {
        let request = try OpenRouterImageAPI.request(baseURL: "https://or.test/api/v1", key: "k",
                                                     model: "m", prompt: "Maler",
                                                     inputImages: [Data([1, 2])], isEdit: true)
        XCTAssertEqual(request.url?.path, "/api/v1/images")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["n"] as? Int, 1)
        XCTAssertNotNil(body?["input_references"])
        let plain = try OpenRouterImageAPI.request(baseURL: "https://or.test/api/v1", key: "k",
                                                   model: "m", prompt: "Maler", inputImages: [],
                                                   isEdit: false)
        let plainBody = try JSONSerialization.jsonObject(with: try XCTUnwrap(plain.httpBody)) as? [String: Any]
        XCTAssertNil(plainBody?["input_references"])
        let pictures = try OpenRouterImageAPI.pictures(from: Data(#"{"data":[{"b64_json":"AQID"}]}"#.utf8))
        XCTAssertEqual(pictures, [Data([1, 2, 3])])
        XCTAssertThrowsError(try OpenRouterImageAPI.pictures(from: Data(#"{"data":[]}"#.utf8)))
        XCTAssertEqual(try OpenRouterImageAPI.imageModelsRequest(baseURL: "https://or.test/api/v1", key: "k")
            .url?.path, "/api/v1/images/models")
        XCTAssertEqual(try OpenRouterImageAPI.imageModels(from: Data(#"{"data":[{"id":"b"},{"id":"a"}]}"#.utf8)),
                       ["a", "b"])
    }

    func testOversizedPicturesAreRejectedBeforeARequestIsBuilt() {
        let oversized = Data(repeating: 0xAB, count: ImagePolicy.uploadByteBudget + 1)
        XCTAssertThrowsError(try OpenRouterImageAPI.request(baseURL: "https://or.test/api/v1", key: "k",
                                                            model: "m", prompt: "Maler",
                                                            inputImages: [oversized], isEdit: true))
        let message = ChatMessage(role: .user, text: "Was ist das?",
                                  images: [Attachment(file: "gross.jpg")])
        XCTAssertThrowsError(try QwenAPI.makeRequest(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                     messages: [message], imageData: [oversized],
                                                     thinking: .nothing))
        XCTAssertThrowsError(try QwenAPI.userRequest(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                     text: "Was ist das?", picture: oversized,
                                                     thinking: .nothing))
    }

    func testTheQwenImageRequests() async throws {
        let request = try QwenAPI.makeImageRequest(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                   prompt: "Leuchtturm", inputImages: [Data([9])],
                                                   isEdit: true)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)
        XCTAssertNotNil(content?.first?["image"])
        MockHTTP.install { request in
            if request.url?.lastPathComponent == "a.png" {
                return (200, FakePictureData.jpeg())
            }
            return (200, Data(#"{"choices":[{"message":{"content":[{"image":"https://img.test/a.png"}]}}]}"#.utf8))
        }
        let urls = try await QwenAPI.generateImage(req: try QwenAPI.makeImageRequest(baseURL: "https://q.test/v1",
                                                                                    key: "k", model: "m",
                                                                                    prompt: "x", inputImages: []))
        XCTAssertEqual(urls.first?.absoluteString, "https://img.test/a.png")
        let downloaded = try await QwenAPI.download(URL(string: "https://img.test/a.png")!)
        XCTAssertFalse(downloaded.isEmpty)
    }

    func testTheQwenImageErrors() async throws {
        MockHTTP.install { _ in (200, Data("{}".utf8)) }
        do {
            _ = try await QwenAPI.generateImage(req: try QwenAPI.makeImageRequest(baseURL: "https://q.test/v1",
                                                                                  key: "k", model: "m",
                                                                                  prompt: "x", inputImages: []))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            _ = try await QwenAPI.download(URL(string: "https://img.test/a.png")!)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.install { _ in (200, Data("kein Bild".utf8)) }
        do {
            _ = try await QwenAPI.download(URL(string: "https://img.test/a.png")!)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheThinkingProbeRequestsAndMessages() throws {
        let level = try ThinkingProbe.levelRequest(baseURL: "https://q.test/v1", key: "k", model: "m")
        let levelBody = try JSONSerialization.jsonObject(with: try XCTUnwrap(level.httpBody)) as? [String: Any]
        XCTAssertEqual(levelBody?["reasoning_effort"] as? String, ThinkingProbe.invalidLevelValue)
        let off = try ThinkingProbe.switchOffRequest(baseURL: "https://q.test/v1", key: "k", model: "m")
        let offBody = try JSONSerialization.jsonObject(with: try XCTUnwrap(off.httpBody)) as? [String: Any]
        XCTAssertEqual(offBody?["enable_thinking"] as? Bool, false)
        XCTAssertEqual(ThinkingProbe.message(from: Data(#"{"message":"direkt"}"#.utf8)), "direkt")
        XCTAssertEqual(ThinkingProbe.message(from: Data(#"{"error":{"message":"genestet"}}"#.utf8)), "genestet")
        XCTAssertEqual(ThinkingProbe.message(from: Data("{}".utf8)), "")
        XCTAssertEqual(ThinkingProbe.levels(in: "reasoning_effort must be one of: low, high"), [.low, .high])
        XCTAssertTrue(ThinkingProbe.levels(in: "kein marker").isEmpty)
        XCTAssertEqual(ThinkingProbe.levelTokens(in: "reasoning_effort is not supported, one of low high").count, 2)
        XCTAssertTrue(ThinkingProbe.levelTokens(in: "irgendwas").isEmpty)
        XCTAssertTrue(ThinkingProbe.deniesParameter("reasoning_effort is not supported"))
        XCTAssertFalse(ThinkingProbe.deniesParameter("reasoning_effort must be one of low high"))
        XCTAssertFalse(ThinkingProbe.deniesParameter("anderer fehler"))
        XCTAssertEqual(ThinkingProbe.reasoningText(from: Data(#"{"choices":[{"message":{"reasoning_content":"denkt"}}]}"#.utf8)),
                       "denkt")
        XCTAssertNil(ThinkingProbe.reasoningText(from: Data("{}".utf8)))
    }

    func testTheModelCapabilitiesAndCatalogDiscovery() {
        var caps = ModelCapabilities()
        XCTAssertFalse(caps.isCurrent(for: .openAI))
        caps.thinking = ThinkingCapabilities(levels: [.low], encoding: .openAI)
        caps.vision = .supported
        XCTAssertTrue(caps.isCurrent(for: .openAI))
        XCTAssertFalse(caps.isCurrent(for: .dashScope))
        struct Entry {
            let name: String
            let value: ModelCapabilities
        }
        let entries = [Entry(name: "a", value: caps), Entry(name: "b", value: caps)]
        let found = ModelCatalogDiscovery.capabilities(of: entries, for: ["a"],
                                                       id: { $0.name }, capabilities: { $0.value })
        XCTAssertEqual(found.keys.sorted(), ["a"])
    }

    func testTheWebSearchHelpers() throws {
        let url = try XCTUnwrap(URL(string: "https://www.example.com/page"))
        XCTAssertEqual(WebSearch.domain(of: url), "example.com")
        XCTAssertEqual(WebSearch.root(ofDomain: "sub.example.com"), "example.com")
        XCTAssertEqual(WebSearch.root(ofDomain: "www.example.com"), "example.com")
        XCTAssertEqual(WebSearch.root(ofDomain: "news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(WebSearch.root(ofDomain: "shop.example.com.au"), "example.com.au")
        XCTAssertFalse(WebSearch.isOwnResult(url))
        XCTAssertTrue(WebSearch.isOwnResult(URL(string: "https://html.duckduckgo.com/html/")!))
        let request = WebSearch.pageRequest(url, accept: "text/html")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), WebSearch.searchUA)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        let search = try WebSearch.searchRequest("gwen test", region: "DE")
        XCTAssertEqual(search.url?.host, "html.duckduckgo.com")
        XCTAssertTrue(search.url?.query?.contains("kl=de-de") == true)
        XCTAssertNil(WebSearch.regionTag("deutschland"))
        XCTAssertEqual(WebSearch.regionTag("de"), "de-de")
        XCTAssertThrowsError(try WebSearch.searchRequest("   "))
        let hit = WebHit(title: "Titel", url: "https://example.com/a", domain: "example.com", text: "Text")
        XCTAssertFalse(hit.sourceBlock(numbered: 1).isEmpty)
        XCTAssertFalse(hit.sourceBlock(numbered: 1, copyOf: 2).isEmpty)
    }

    func testTheSearchParsesDuckDuckGoHTML() async throws {
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("html.duckduckgo.com") {
                let html = """
                <a class="result__a" href="https://example.com/eins">Ergebnis Eins</a>
                <a class="result__a" href="https://zweite.test/zwei">Ergebnis Zwei</a>
                <a class="result__a" href="https://example.com/doppelt">Doppelte Domain</a>
                <a class="result__a" href="https://html.duckduckgo.com/own">Eigenes Ergebnis</a>
                """
                return (200, Data(html.utf8))
            }
            let body = "<html><head><title>Testseite</title></head><body><p>"
                + String(repeating: "Ein langer Text über das Wetter. ", count: 20)
                + "</p></body></html>"
            return (200, Data(body.utf8))
        }
        let urls = try await WebSearch.searchURLs("wetter")
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.host, "example.com")
        let hit = try await WebSearch.fetchText(URL(string: "https://example.com/eins")!)
        XCTAssertFalse(hit.text.isEmpty)
        XCTAssertEqual(hit.title, "Testseite")
    }
}
