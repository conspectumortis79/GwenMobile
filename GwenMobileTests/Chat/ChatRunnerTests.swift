@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private func steadyAnswer(_ chunks: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        chunks.forEach { continuation.yield($0) }
        continuation.finish()
    }
}

private func failingAnswer(_ chunks: [String], _ error: Error) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        chunks.forEach { continuation.yield($0) }
        continuation.finish(throwing: error)
    }
}

private func answerRequest(_ name: String) -> URLRequest {
    URLRequest(url: URL(string: "https://example.invalid/\(name)")!)
}

@MainActor
final class ChatRunnerTests: XCTestCase {
    private func collect(_ target: LockedValue<[String]>) -> @MainActor (String) -> Void {
        { chunk in target.mutate { $0.append(chunk) } }
    }

    func testRunCollectsTheChunksInOrderAndReturnsTheWholeAnswer() async throws {
        let seen = LockedValue([String]())
        let runner = ChatRunner { _ in steadyAnswer(["hallo", " welt"]) }
        let text = try await runner.run(answerRequest("ganz"), onChunk: collect(seen))
        XCTAssertEqual(text, "hallo welt")
        XCTAssertEqual(seen.current, ["hallo", " welt"])
    }

    func testAFailingAnswerKeepsThePartialTextAsRecoveredText() async throws {
        let runner = ChatRunner { _ in failingAnswer(["anfang"], APIError(message: "HTTP 500", status: 500)) }
        do {
            _ = try await runner.run(answerRequest("fehler"), onChunk: { _ in })
            XCTFail("Der Fehler muss beim Aufrufer ankommen")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 500)
            XCTAssertEqual(error.recoveredText, "anfang")
        }
    }
}
