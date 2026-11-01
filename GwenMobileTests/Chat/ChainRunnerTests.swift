@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
private func chainRouted(_ text: String, _ plan: SendPlan, convID: UUID,
                         messages: [ChatMessage] = []) -> RoutedSend {
    RoutedSend(text: text, plan: plan, turn: ModelTurn(messages: messages, images: []),
               history: messages, attachments: [], files: [], convID: convID, started: Date())
}

@MainActor
private func chainImageData() throws -> Data {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { context in
        UIColor.systemGreen.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
    }
    return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
}

@MainActor
final class ChainRunnerTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
        TranslationFlow.runOverride = nil
    }

    override func tearDown() async throws {
        TranslationFlow.runOverride = nil
        MockHTTP.uninstall()
        hosted.close()
        try await super.tearDown()
    }

    private func makeView(_ prefix: String) async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix))
        AppSettings.shared.setKey("chain-test-key", for: AppSettings.shared.provider)
        setTestModels()
        return (try await hosted.open(store, in: self), store)
    }

    private func setTestModels() {
        let provider = AppSettings.shared.provider
        AppSettings.shared.updateProfile(of: provider) { profile in
            if profile.chatModel.isEmpty { profile.chatModel = "test-chat-model" }
            if profile.imageModel.isEmpty { profile.imageModel = "test-image-model" }
            if profile.visionModel.isEmpty { profile.visionModel = "test-vision-model" }
            if profile.videoModel.isEmpty { profile.videoModel = "test-video-model" }
            if profile.videoGenerationModel.isEmpty {
                profile.videoGenerationModel = "test-video-generation-model"
            }
        }
    }

    func testTheRunnerCarriesAnImageThroughATextStepIntoTheEdit() async throws {
        AppSettings.shared.provider = .openRouter
        AppSettings.shared.setKey("chain-image-key", for: .openRouter)
        let (view, store) = try await makeView("chain-run-image")
        let convID = try XCTUnwrap(store.current?.id)
        let jpeg = try chainImageData()
        let imageCalls = LockedValue(0)
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("images") {
                imageCalls.mutate { $0 += 1 }
                return (200, Data(#"{"data":[{"b64_json":"\#(jpeg.base64EncodedString())"}]}"#.utf8))
            }
            if address.contains("chat/completions") {
                return (200, MockHTTP.sse("Der Hund sitzt."))
            }
            return (200, Data("{}".utf8))
        }
        let create = ToolDecision(route: .imageCreate, picturePrompt: "Ein Hund")
        let chat = ToolDecision(route: .chat)
        let edit = ToolDecision(route: .imageEdit, pictureMonochrome: true)
        let plan = SendPlan(actions: [create, chat, edit])
        let message = ChatMessage(role: .user, text: "Male einen Hund, beschreibe ihn und mach ihn schwarz-weiß")
        await view.run(chainRouted(message.text, plan, convID: convID, messages: [message]))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(imageCalls.current, 1, "der lokale Schwarz-Weiß-Schritt braucht kein zweites Bildmodell")
        let answer = try XCTUnwrap(store.current?.messages.last)
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertEqual(answer.outImages?.count, 2)
        XCTAssertTrue(answer.text.contains("Der Hund sitzt."), answer.text)
    }

    func testAChatWishAnswersOnlyItselfAndSearchesWithItsOwnWords() async throws {
        let (view, store) = try await makeView("chain-run-wish-focus")
        let convID = try XCTUnwrap(store.current?.id)
        let answered = LockedValue<[String]>([])
        let searched = LockedValue<[String]>([])
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("duckduckgo") {
                searched.mutate { $0.append(address) }
                return (200, Data("<html></html>".utf8))
            }
            if address.contains("chat/completions") {
                answered.mutate { $0.append(MockHTTP.body(of: request)) }
                return (200, MockHTTP.sse("[[SEARCH]]"))
            }
            return (200, Data("{}".utf8))
        }
        var chat = ToolDecision(route: .chat)
        chat.wish = "Wer hat das Turnier gewonnen?"
        var clock = ToolDecision(route: .clock(ClockRequest(timeZone: "Asia/Tokyo", place: "Tokio")))
        clock.wish = "Wie spät ist es in Tokio?"
        let message = ChatMessage(role: .user, text: "Wer hat das Turnier gewonnen? Und wie spät ist es in Tokio?")
        await view.run(chainRouted(message.text, SendPlan(actions: [chat, clock]), convID: convID,
                                   messages: [message]))
        try await Task.sleep(for: .milliseconds(400))
        let first = try XCTUnwrap(answered.current.first)
        XCTAssertTrue(first.contains("This step answers only wish 1: Wer hat das Turnier gewonnen?"), first)
        let address = try XCTUnwrap(searched.current.first)
        XCTAssertTrue(address.contains("Turnier"), address)
        XCTAssertFalse(address.contains("Tokio"), "die Suche gehört nur zum eigenen Wunsch: \(address)")
    }

    func testTheRunnerFeedsAPriceResultIntoTheNextStep() async throws {
        let (view, store) = try await makeView("chain-run-price")
        let convID = try XCTUnwrap(store.current?.id)
        let streamed = LockedValue<[String]>([])
        let chatCalls = LockedValue(0)
        let page = "<html><head><title>Shop</title></head><body><p>"
            + String(repeating: "Ein langer Text mit Preis. ", count: 20)
            + "199 Euro</p></body></html>"
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("duckduckgo") {
                let html = #"<a class="result__a" href="https://shop.test/a">Shop Angebot</a>"#
                return (200, Data(html.utf8))
            }
            if address.contains("chat/completions") {
                let call = chatCalls.mutate { value in
                    value += 1
                    return value
                }
                guard call > 1 else { return (200, MockHTTP.completion("Der Preis liegt bei 199 Euro. [1]")) }
                streamed.mutate { $0.append(MockHTTP.body(of: request)) }
                return (200, MockHTTP.sse("Die Bewertungen sind gut."))
            }
            return (200, Data(page.utf8))
        }
        let price = ToolDecision(route: .priceSearch(terms: ["MacBook"], country: "DE", nearby: false))
        let chat = ToolDecision(route: .chat)
        let message = ChatMessage(role: .user, text: "Vergleiche den Preis und recherchiere die Bewertungen")
        await view.run(chainRouted(message.text, SendPlan(actions: [price, chat]), convID: convID,
                                   messages: [message]))
        try await Task.sleep(for: .milliseconds(800))
        let bodies = streamed.current
        XCTAssertFalse(bodies.isEmpty)
        XCTAssertTrue(bodies.contains { $0.contains("199 Euro") },
                      "die Preisantwort muss im Kontext des nächsten Schritts stehen")
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("199 Euro") } ?? false)
    }

    func testTheRunnerTranslatesTheFreshChainAnswer() async throws {
        let (view, store) = try await makeView("chain-run-translate")
        let convID = try XCTUnwrap(store.current?.id)
        let seen = LockedValue<TranslationJob?>(nil)
        TranslationFlow.runOverride = { job, _ in
            seen.set(job)
            return TranslationResult(text: "The summary.", signature: "stub", onDevice: true)
        }
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("chat/completions") {
                return (200, MockHTTP.sse("Die Zusammenfassung."))
            }
            return (200, Data("{}".utf8))
        }
        let chat = ToolDecision(route: .chat)
        let translate = ToolDecision(route: .translate(TranslationJob(text: "", targetCode: "en")))
        let message = ChatMessage(role: .user, text: "Fasse zusammen und übersetze das")
        await view.run(chainRouted(message.text, SendPlan(actions: [chat, translate]), convID: convID,
                                   messages: [message]))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(seen.current?.text, "Die Zusammenfassung.")
        XCTAssertTrue(store.current?.messages.contains { $0.text == "The summary." } ?? false)
    }

    func testTheRunnerKeepsTheNextAnswerAfterDeletingTheHistory() async throws {
        let (view, store) = try await makeView("chain-run-history")
        let convID = try XCTUnwrap(store.current?.id)
        let history = ToolDecision(route: .history)
        let clock = ToolDecision(route: .clock(ClockRequest(timeZone: "Asia/Tokyo", place: "Tokio")))
        let message = ChatMessage(role: .user, text: "Lösche alle Verläufe und sag mir die Uhrzeit in Tokio")
        await view.run(chainRouted(message.text, SendPlan(actions: [history, clock]), convID: convID,
                                   messages: [message]))
        try await Task.sleep(for: .milliseconds(300))
        let answers = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 2)
        XCTAssertTrue(answers.last?.text.contains("Tokio") ?? false, answers.last?.text ?? "")
    }

    func testAnOldGalleryDoesNotBecomeTheTargetOfANewEdit() async throws {
        let (view, store) = try await makeView("chain-run-gallery")
        let convID = try XCTUnwrap(store.current?.id)
        let oldUser = ChatMessage(role: .user, text: "Zeig mir Bilder")
        store.appendMessage(oldUser, to: convID)
        let file = try XCTUnwrap(store.media.storeImageData(FakePictureData.jpeg()))
        let gallery = PictureGallery(query: "Bilder", pictures: [
            WebPicture(file: file, pageURL: "https://q.test/a", fullURL: "https://q.test/a.jpg",
                       title: "Alt", domain: "q.test"),
        ])
        store.appendMessage(ChatMessage(role: .assistant, text: "Galerie", gallery: gallery), to: convID)
        store.appendMessage(ChatMessage(role: .user, text: "Mach ein neues Bild schwarz-weiß"), to: convID)
        let fresh = await view.turnWithFoundPicture(for: ModelTurn(messages: [], images: []))
        XCTAssertTrue(fresh.images.isEmpty, "eine alte Galerie ist kein Ziel für diese Nachricht")
        store.appendMessage(ChatMessage(role: .assistant, text: "Neue Galerie", gallery: gallery), to: convID)
        let found = await view.turnWithFoundPicture(for: ModelTurn(messages: [], images: []))
        XCTAssertEqual(found.pictureFiles, [file])
    }
}

@MainActor
final class ChainParallelTests: GwenTestCase {
    private let hosted = HostedChatView()
    private var previousProvider = ProviderID.qwenCloud

    override func setUp() async throws {
        try await super.setUp()
        previousProvider = AppSettings.shared.provider
        AppSettings.shared.provider = .openRouter
        AppSettings.shared.setKey("parallel-test-key", for: .openRouter)
        MockHTTP.install(MockHTTP.defaultHandler)
        TranslationFlow.runOverride = nil
    }

    override func tearDown() async throws {
        AppSettings.shared.provider = previousProvider
        TranslationFlow.runOverride = nil
        MockHTTP.uninstall()
        hosted.close()
        try await super.tearDown()
    }

    private func makeView(_ prefix: String) async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix))
        let provider = AppSettings.shared.provider
        AppSettings.shared.updateProfile(of: provider) { profile in
            if profile.chatModel.isEmpty { profile.chatModel = "test-chat-model" }
            if profile.imageModel.isEmpty { profile.imageModel = "test-image-model" }
            if profile.visionModel.isEmpty { profile.visionModel = "test-vision-model" }
            if profile.videoModel.isEmpty { profile.videoModel = "test-video-model" }
            if profile.videoGenerationModel.isEmpty {
                profile.videoGenerationModel = "test-video-generation-model"
            }
        }
        return (try await hosted.open(store, in: self), store)
    }

    private func wish(_ route: SendRoute, _ words: String, standalone: Bool = true) -> ToolDecision {
        var decision = ToolDecision(route: route)
        decision.wish = words
        decision.standalone = standalone
        return decision
    }

    func testTheFasterWishWaitsForTheEarlierOneInTheChat() async throws {
        let (view, store) = try await makeView("chain-order")
        let convID = try XCTUnwrap(store.current?.id)
        MockHTTPProtocol.dataDelay = 0.25
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("chat/completions") == true else {
                return (200, Data("{}".utf8))
            }
            return (200, MockHTTP.sse("Die Zugspitze ist 2962 Meter hoch."))
        }
        let question = "Wie hoch ist die Zugspitze? Und wie ist der Stand der App?"
        let plan = SendPlan(actions: [wish(.chat, "Wie hoch ist die Zugspitze?"), wish(.appStatus, "App-Stand")])
        await view.run(chainRouted(question, plan, convID: convID,
                                   messages: [ChatMessage(role: .user, text: question)]))
        try await Task.sleep(for: .milliseconds(900))
        let answers = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 2, "zwei Schritte ohne gemeinsame Antwort schreiben zwei Blasen")
        XCTAssertTrue(answers[0].text.contains("2962"), answers[0].text)
        XCTAssertFalse(answers[1].text.contains("2962"),
                       "der schnelle zweite Schritt wartet auf den langsameren ersten")
    }

    func testTwoIndependentWishesDoNotReadEachOthersAnswer() async throws {
        let (view, store) = try await makeView("chain-standalone")
        let convID = try XCTUnwrap(store.current?.id)
        let bodies = LockedValue<[String]>([])
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("chat/completions") == true else {
                return (200, Data("{}".utf8))
            }
            let body = MockHTTP.body(of: request)
            bodies.mutate { $0.append(body) }
            return (200, MockHTTP.sse(body.contains("wish 2") ? "Antwort zwei." : "Antwort eins."))
        }
        let question = "Wer ist Natalie Portman? Und wie hoch ist die Zugspitze?"
        let plan = SendPlan(actions: [wish(.chat, "Wer ist Natalie Portman?"),
                                      wish(.chat, "Wie hoch ist die Zugspitze?")])
        await view.run(chainRouted(question, plan, convID: convID,
                                   messages: [ChatMessage(role: .user, text: question)]))
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(bodies.current.count, 2)
        let second = bodies.current.first { $0.contains("wish 2") } ?? ""
        XCTAssertFalse(second.contains("Antwort eins"),
                       "der zweite Wunsch braucht den ersten nicht und liest ihn nicht")
        let answers = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 1, "beide Antworten stehen in einer Blase")
        XCTAssertTrue(answers[0].text.hasPrefix("Antwort eins."), answers[0].text)
        XCTAssertTrue(answers[0].text.hasSuffix("Antwort zwei."), answers[0].text)
    }

    func testADependentWishStillReadsTheAnswerBeforeIt() async throws {
        let (view, store) = try await makeView("chain-dependent")
        let convID = try XCTUnwrap(store.current?.id)
        let bodies = LockedValue<[String]>([])
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("chat/completions") == true else {
                return (200, Data("{}".utf8))
            }
            let body = MockHTTP.body(of: request)
            bodies.mutate { $0.append(body) }
            return (200, MockHTTP.sse(body.contains("wish 2") ? "Antwort zwei." : "Antwort eins."))
        }
        let question = "Fasse die erste Sache zusammen und dann die zweite."
        let plan = SendPlan(actions: [wish(.chat, "Fasse die erste Sache zusammen.", standalone: false),
                                      wish(.chat, "Fasse die zweite Sache zusammen.", standalone: false)])
        await view.run(chainRouted(question, plan, convID: convID,
                                   messages: [ChatMessage(role: .user, text: question)]))
        try await Task.sleep(for: .milliseconds(700))
        let second = bodies.current.first { $0.contains("wish 2") } ?? ""
        XCTAssertTrue(second.contains("Antwort eins"),
                      "ein Wunsch ohne eigene Unabhängigkeit bekommt die frühere Antwort")
    }

    func testThreeSeparatePicturesAreAskedTogetherAndLandInOneBubble() async throws {
        let (view, store) = try await makeView("chain-pictures")
        let convID = try XCTUnwrap(store.current?.id)
        let asked = LockedValue<[String]>([])
        let jpeg = try chainImageData()
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("images") == true else {
                return (200, Data("{}".utf8))
            }
            asked.mutate { $0.append(MockHTTP.body(of: request)) }
            return (200, Data(#"{"data":[{"b64_json":"\#(jpeg.base64EncodedString())"}]}"#.utf8))
        }
        let prompts = ["a red circle", "a blue square", "a green triangle"]
        let plan = SendPlan(actions: prompts.map { prompt in
            var decision = ToolDecision(route: .imageCreate, picturePrompt: prompt)
            decision.wish = "Male " + prompt
            decision.standalone = true
            return decision
        })
        XCTAssertEqual(ChainSchedule.stages(plan.actions), [[0, 1, 2]],
                       "drei getrennte Bilder laufen in einer Stufe")
        let question = "Male einen roten Kreis, ein blaues Quadrat und ein grünes Dreieck."
        await view.run(chainRouted(question, plan, convID: convID,
                                   messages: [ChatMessage(role: .user, text: question)]))
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(asked.current.count, 3, "jedes Bild wird einmal angefragt")
        XCTAssertTrue(prompts.allSatisfy { prompt in asked.current.contains { $0.contains(prompt) } },
                      asked.current.joined(separator: " | "))
        let answers = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 1, "die drei Bilder stehen in einer Blase")
        XCTAssertEqual(answers.first?.outImages?.count, 3)
        XCTAssertEqual(Set(answers.first?.outImages?.map(\.file) ?? []).count, 3,
                       "jedes Bild hat seine eigene Datei")
    }

    func testATwoPictureChainDoesNotBlockTheIndependentPicture() async throws {
        let (view, store) = try await makeView("chain-picture-mix")
        let convID = try XCTUnwrap(store.current?.id)
        let asked = LockedValue<[String]>([])
        let jpeg = try chainImageData()
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("images") == true else {
                return (200, Data("{}".utf8))
            }
            asked.mutate { $0.append(MockHTTP.body(of: request)) }
            return (200, Data(#"{"data":[{"b64_json":"\#(jpeg.base64EncodedString())"}]}"#.utf8))
        }
        var chain = ToolDecision(route: .imageCreate, picturePrompt: "a purple hexagon")
        chain.wish = "Male ein lila Sechseck"
        chain.standalone = true
        var change = ToolDecision(route: .imageEdit, pictureInstruction: "in schwarz-weiß",
                                  pictureMonochrome: true)
        change.wish = "Mach das Bild schwarz-weiß"
        change.standalone = false
        var star = ToolDecision(route: .imageCreate, picturePrompt: "an orange star")
        star.wish = "Male einen orangen Stern"
        star.standalone = true
        let plan = SendPlan(actions: [chain, change, star])
        XCTAssertEqual(ChainSchedule.stages(plan.actions), [[0, 2], [1]],
                       "erst die zwei Bilder, dann die Änderung an einem davon")
        let question = "Male ein lila Sechseck, mach es schwarz-weiß und male einen orangen Stern."
        await view.run(chainRouted(question, plan, convID: convID,
                                   messages: [ChatMessage(role: .user, text: question)]))
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(asked.current.count, 2, "die Änderung rechnet auf dem Gerät, sie fragt nichts an")
        let answers = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers.first?.outImages?.count, 3, "zwei Bilder und die Änderung")
        XCTAssertEqual(Set(answers.first?.outImages?.map(\.file) ?? []).count, 3)
    }

    func testAFinishedPictureShowsUpWhileTheChainStillRuns() async throws {
        var (view, store) = try await makeView("chain-picture-early")
        let convID = try XCTUnwrap(store.current?.id)
        let jpeg = try chainImageData()
        MockHTTP.install { request in
            guard request.url?.absoluteString.contains("images") == true else {
                return (200, Data("{}".utf8))
            }
            return (200, Data(#"{"data":[{"b64_json":"\#(jpeg.base64EncodedString())"}]}"#.utf8))
        }
        view.chatRunner = { _, onChunk in
            try? await Task.sleep(for: .milliseconds(900))
            onChunk("Langsame Antwort.")
            return "Langsame Antwort."
        }
        var chat = ToolDecision(route: .chat)
        chat.wish = "Wer ist Natalie Portman?"
        chat.standalone = true
        var picture = ToolDecision(route: .imageCreate, picturePrompt: "a red circle")
        picture.wish = "Male einen roten Kreis"
        picture.standalone = true
        let plan = SendPlan(actions: [chat, picture])
        XCTAssertEqual(ChainSchedule.stages(plan.actions), [[0, 1]])
        let question = "Wer ist Natalie Portman? Und male einen roten Kreis."
        let run = Task { @MainActor in
            await view.run(chainRouted(question, plan, convID: convID,
                                       messages: [ChatMessage(role: .user, text: question)]))
        }
        try await Task.sleep(for: .milliseconds(700))
        let early = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(early.flatMap { $0.outImages ?? [] }.count, 1,
                       "das fertige Bild steht schon in der Blase, während der Chat noch läuft")
        await run.value
        let final = (store.current?.messages ?? []).filter { $0.role == .assistant }
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final.flatMap { $0.outImages ?? [] }.count, 1,
                       "das Bild steht nur einmal in der Blase")
        XCTAssertTrue(final.first?.text.contains("Langsame Antwort") ?? false, final.first?.text ?? "")
    }

    func testALocalModelNeverGetsTwoStepsAtOnce() async throws {
        let (view, _) = try await makeView("chain-limit")
        AppSettings.shared.provider = .local
        XCTAssertEqual(view.chainParallelSteps, 1)
        AppSettings.shared.provider = .openRouter
        XCTAssertEqual(view.chainParallelSteps, ChainSchedule.inFlight)
    }

}
