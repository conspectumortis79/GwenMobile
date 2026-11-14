@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ProfileStorageTests: XCTestCase {
    func testProviderKeyedDictionariesEncodeAsJSONObjects() throws {
        let data = try JSONEncoder().encode([ProviderID.openRouter: "k"])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["openrouter"] as? String, "k")
        XCTAssertEqual(try JSONDecoder().decode([ProviderID: String].self, from: Data(#"{"openai":""}"#.utf8)),
                       [.openAICompatible: ""])
    }

    func testCurrentAndLegacyProfileStoresBothDecode() throws {
        let profile = ProviderProfile(chatModel: "qwen3.8-flash", availableModels: ["qwen3.8-flash"])
        let keyed = try JSONEncoder().encode([ProviderID.qwenCloud: profile])
        XCTAssertEqual(ProfileStorage.decode(keyed), [.qwenCloud: profile])
        let profileJSON = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        let legacy = Data(#"["qwen",\#(profileJSON),"openrouter",\#(profileJSON),"kaputt",{}]"#.utf8)
        let decoded = ProfileStorage.decode(legacy)
        XCTAssertEqual(decoded[.qwenCloud], profile)
        XCTAssertEqual(decoded[.openRouter], profile)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(ProfileStorage.decode(nil), [:])
        XCTAssertEqual(ProfileStorage.decode(Data("nicht json".utf8)), [:])
    }
}
