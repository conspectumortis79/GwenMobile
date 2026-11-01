@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugStructuredProbe {
    static func run() async {
        let report = SweepReport(file: "structured_tools.txt")
        let resolvedFollowUp = toolCall(ToolRouter.resolveQueryTool,
                                        ["status": "resolved",
                                         "query": "Hauptursachen der Klimaerwärmung in Deutschland"])
        let unresolvedFollowUp = toolCall(ToolRouter.resolveQueryTool,
                                          ["status": "unresolved", "query": ""])
        report.add("FOLLOWUP_RESOLVED", FollowUpResolver.resolvedQuery(from: resolvedFollowUp) ?? "nil")
        report.add("FOLLOWUP_UNRESOLVED", FollowUpResolver.resolvedQuery(from: unresolvedFollowUp) == nil
                   ? "nil" : "unerwartet")

        let resolvedImage = toolCall(ToolRouter.composeImagePromptTool,
                                     ["status": "resolved",
                                      "prompt": "Ein Leuchtturm im Sturm, Ölgemälde"])
        let unresolvedImage = toolCall(ToolRouter.composeImagePromptTool,
                                       ["status": "unresolved", "prompt": ""])
        report.add("IMAGE_RESOLVED", ImagePromptComposer.prompt(from: resolvedImage) ?? "nil")
        report.add("IMAGE_UNRESOLVED", ImagePromptComposer.prompt(from: unresolvedImage) == nil
                   ? "nil" : "unerwartet")

        let translated = toolCall(ToolRouter.reportTranslationTool, ["translation": "Bonjour"])
        let emptyTranslation = toolCall(ToolRouter.reportTranslationTool, ["translation": "   "])
        report.add("TRANSLATION_RESOLVED", ModelTranslation.translation(from: translated) ?? "nil")
        report.add("TRANSLATION_EMPTY", ModelTranslation.translation(from: emptyTranslation) == nil
                   ? "nil" : "unerwartet")

        let followRequest = try? QwenAPI.userRequest(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                     text: "und in Deutschland?", picture: nil,
                                                     thinking: .nothing)
        report.add("FOLLOWUP_REQUEST", requestLine(followRequest, tool: ToolRouter.resolveQueryTool))

        let imageHistory = [ChatMessage(role: .assistant, text: "Ein Leuchtturm im Sturm.")]
        let imageRequest = try? QwenAPI.composeImagePromptRequest(baseURL: "https://q.test/v1", key: "k",
                                                                  model: "m", instruction: "mach daraus ein bild",
                                                                  history: imageHistory, pictures: 1,
                                                                  thinking: .nothing)
        report.add("IMAGE_REQUEST", requestLine(imageRequest, tool: ToolRouter.composeImagePromptTool))

        let credentials = TranslationCredentials(baseURL: "https://q.test/v1", apiKey: "k", model: "m",
                                                 thinking: .nothing)
        let translationRequest = try? ModelTranslation.makeRequest(
            TranslationJob(text: "Hallo", targetCode: "fr", sourceCode: "de"), credentials: credentials)
        report.add("TRANSLATION_REQUEST", requestLine(translationRequest,
                                                       tool: ToolRouter.reportTranslationTool))
        flowLog.info("STRUCTURED fertig")
    }

    static func live(_ view: ChatView) async {
        let report = SweepReport(file: "structured_live.txt")
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: false)
        let imageModel = settings.chatModel
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let host = URL(string: baseURL)?.host ?? "-"
        report.add("KONFIG", "provider=\(settings.provider.rawValue) modell=\(model) bildmodell=\(imageModel) "
                   + "host=\(host) schluessel=\(!key.isEmpty) konfiguriert=\(settings.isConfigured)")
        guard settings.isConfigured, !key.isEmpty else {
            report.add("ABBRUCH", "nicht konfiguriert")
            flowLog.info("STRUCTUREDLIVE nicht konfiguriert")
            return
        }

        let history = [ChatMessage(role: .user, text: "Was sind die Hauptursachen der Klimaerwärmung?"),
                       ChatMessage(role: .assistant,
                                   text: "Fossile Energieträger, Industrie, Landwirtschaft und Abholzung."),
                       ChatMessage(role: .user, text: "und in Deutschland?")]
        do {
            let started = ContinuousClock.now
            let thinking = settings.thinkingOffDirective(for: model)
            let query = try await QwenAPI.resolveQuery(baseURL: baseURL, key: key, model: model,
                                                       history: history, thinking: thinking)
            let usable = query.map { FollowUpResolver.isUsable($0, insteadOf: "und in Deutschland?") } ?? false
            report.add("FOLLOWUP", "dauer_ms=\(msOf(started.duration(to: .now))) nutzbar=\(usable) "
                       + "abfrage=\(TextLine.oneLine(query ?? "nil", limit: 160))")
        } catch {
            report.addFailure("FOLLOWUP", error)
        }

        let imageHistory = [ChatMessage(role: .assistant, text: "Ein Leuchtturm im Sturm, Ölgemälde."),
                            ChatMessage(role: .user, text: "mach daraus ein bild")]
        await liveImage(report, label: "IMAGE_DIRECT", baseURL: baseURL, key: key, model: imageModel,
                        instruction: "Male einen Leuchtturm im Sturm als Ölgemälde.", history: [],
                        thinking: settings.thinkingOffDirective(for: imageModel))
        await liveImage(report, label: "IMAGE_CONTEXT", baseURL: baseURL, key: key, model: imageModel,
                        instruction: "mach daraus ein bild", history: imageHistory,
                        thinking: settings.thinkingOffDirective(for: imageModel))

        let translationModel = settings.chatModel
        do {
            let started = ContinuousClock.now
            let credentials = TranslationCredentials(baseURL: baseURL, apiKey: key, model: translationModel,
                                                     thinking: settings.thinkingOffDirective(for: translationModel))
            let job = TranslationJob(text: "Guten Morgen, wie geht es dir?", targetCode: "fr", sourceCode: "de")
            let translated = try await ModelTranslation.translate(job, credentials: credentials)
            report.add("TRANSLATION", "dauer_ms=\(msOf(started.duration(to: .now))) text="
                       + TextLine.oneLine(translated, limit: 180))
        } catch {
            report.addFailure("TRANSLATION", error)
        }
        flowLog.info("STRUCTUREDLIVE fertig")
    }

    private static func liveImage(_ report: SweepReport, label: String, baseURL: String, key: String,
                                  model: String, instruction: String, history: [ChatMessage],
                                  thinking: ThinkingDirective) async {
        do {
            let started = ContinuousClock.now
            let request = try QwenAPI.composeImagePromptRequest(baseURL: baseURL, key: key, model: model,
                                                                instruction: instruction, history: history,
                                                                pictures: 1, thinking: thinking)
            let data = try await HTTP.jsonData(request)
            let calls = ToolRouter.toolCalls(from: data)
            let arguments = ToolRouter.arguments(from: data, named: ToolRouter.composeImagePromptTool)
            let status = arguments?["status"] as? String ?? "-"
            let rawPrompt = arguments?["prompt"] as? String ?? ""
            let content = ToolRouter.firstChoice(from: data)?.message["content"] as? String ?? "-"
            report.add("\(label)_RAW", "aufrufe=\(calls.map(\.name).joined(separator: ",")) status=\(status) "
                       + "prompt_zeichen=\(rawPrompt.count) content=\(TextLine.oneLine(content, limit: 120))")
            let prompt = ImagePromptComposer.usablePrompt(ImagePromptComposer.prompt(from: data),
                                                          insteadOf: instruction)
            report.add(label, "dauer_ms=\(msOf(started.duration(to: .now))) prompt="
                       + TextLine.oneLine(prompt ?? "nil", limit: 180))
        } catch {
            report.addFailure(label, error)
        }
    }

    private static func toolCall(_ name: String, _ arguments: [String: Any]) -> Data {
        let raw = (try? JSONSerialization.data(withJSONObject: arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let call: [String: Any] = ["id": "c1", "type": "function",
                                   "function": ["name": name, "arguments": raw]]
        let body: [String: Any] = ["choices": [["message": ["content": NSNull(), "tool_calls": [call]]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    private static func requestLine(_ request: URLRequest?, tool: String) -> String {
        guard let request, let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return "request=fehlt"
        }
        let choice = object["tool_choice"] as? String ?? "-"
        let tools = (object["tools"] as? [[String: Any]] ?? []).compactMap {
            ($0["function"] as? [String: Any])?["name"] as? String
        }
        return "wahl=\(choice) werkzeuge=\(tools.joined(separator: ",")) erwartet=\(tool)"
    }
}
#endif
