@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import UIKit

@MainActor
enum DebugLocalProbe {
    static let reportFile = "local_probe.txt"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let settings = view.settings
        cleanFlatFiles()
        let installed = LocalModelFiles().installedIDs()
        report.add("MARKE", "localprobe-v1")
        report.add("SPEICHER", "frei=\(LocalMemory.available) phys=\(LocalMemory.physical) "
                   + "label=\(LocalMemory.label)")
        report.add("INSTALLIERT", installed.joined(separator: ","))
        guard let model = installed.first(where: { $0.lowercased().contains("qwen3.5") })
                ?? installed.first(where: { $0.lowercased().contains("e4b") })
                ?? installed.first else {
            report.add("MODELL", "keins")
            return
        }
        report.add("MODELL", model)
        let profile = settings.profile(of: .local)
        report.add("LISTE", "modelle=\(installed.joined(separator: ",")) "
                   + "chat=\(profile.chatModel) vision=\(profile.visionModel) "
                   + "provider=\(settings.provider.rawValue)")
        await plan(report)
        await chat(report, model: model)
        await stream(report, model: model)
        await tool(report, model: model)
        await router(report, model: model, settings: settings)
        await vision(report, model: model)
        await thinking(report, model: model)
        report.add("SPEICHER_ENDE", "frei=\(LocalMemory.available)")
        await LocalEngine.shared.unload()
        report.add("ENDE", "ok")
    }

    private static func cleanFlatFiles() {
        let files = LocalModelFiles()
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: files.root.path) else { return }
        for name in names {
            let url = files.root.appendingPathComponent(name)
            var directory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
            if !directory.boolValue || name.hasSuffix(".partial") {
                try? manager.removeItem(at: url)
            }
        }
    }

    private static func plan(_ report: SweepReport) async {
        do {
            let downloader = LocalModelDownloader()
            let started = Date()
            guard let choice = LocalModelFiles().installedChoices().first else {
                report.add("PLAN", "kein installiertes Modell")
                return
            }
            let plan = try await downloader.plan(for: choice)
            report.add("PLAN", "dateien=\(plan.files.count) bytes=\(plan.totalBytes) "
                       + "ms=\(milliseconds(since: started))")
            if let config = plan.files.first(where: { $0.path == "config.json" }) {
                let target = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gwen-local-config.json")
                try await downloader.download(config, to: target) { _, _ in }
                let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size]
                    as? NSNumber)?.int64Value ?? 0
                report.add("TRANSFER", "bytes=\(size) ms=\(milliseconds(since: started))")
                try? FileManager.default.removeItem(at: target)
            }
        } catch {
            report.addFailure("PLAN", error)
        }
    }

    private static func chat(_ report: SweepReport, model: String) async {
        let request = LocalChatRequest(model: model,
                                       messages: [LocalMessage(role: .user,
                                                               text: "Antworte mit genau: Lokal geht.")],
                                       tools: [], maxTokens: 96,
                                       thinking: false, temperature: 0)
        let started = Date()
        do {
            let result = try await LocalEngine.shared.run(request)
            report.add("CHAT", "text=\(TextLine.oneLine(result.text, limit: 160)) "
                       + "tokens=\(result.promptTokens)/\(result.completionTokens) "
                       + "grund=\(result.finishReason) ms=\(milliseconds(since: started))")
        } catch {
            report.addFailure("CHAT", error)
        }
    }

    private static func stream(_ report: SweepReport, model: String) async {
        do {
            let body: [String: Any] = [
                "model": model,
                "stream": true,
                "max_tokens": 96,
                "messages": [["role": "user", "content": "Zähle laut: eins, zwei, drei."]],
            ]
            let request = try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(LocalEndpoint.baseURL),
                                            key: "", body: body, timeout: 300,
                                            accept: "text/event-stream")
            let started = Date()
            var text = ""
            var first: Date?
            for try await chunk in QwenAPI.streamText(req: request) {
                if first == nil { first = Date() }
                text += chunk
            }
            let firstMs = first.map { milliseconds(since: started, to: $0) } ?? -1
            report.add("STREAM", "text=\(TextLine.oneLine(text, limit: 160)) chars=\(text.count) "
                       + "erstes=\(firstMs)ms gesamt=\(milliseconds(since: started))ms")
        } catch {
            report.addFailure("STREAM", error)
        }
    }

    private static func tool(_ report: SweepReport, model: String) async {
        do {
            let tools: [[String: Any]] = [[
                "type": "function",
                "function": [
                    "name": "create_appointment",
                    "description": "Creates a calendar appointment.",
                    "parameters": [
                        "type": "object",
                        "properties": ["title": ["type": "string"], "start": ["type": "string"]],
                        "required": ["title", "start"],
                    ],
                ],
            ]]
            let body = ToolRouter.toolRequestBody(
                model: model, maxTokens: 700, stream: false,
                messages: [ChatPayload.system("Du bist ein Router. Rufe das passende Tool auf."),
                           ChatPayload.user("Trag morgen um 14 Uhr einen Zahnarzttermin ein.")],
                tools: tools)
            let request = try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(LocalEndpoint.baseURL),
                                            key: "", body: body, timeout: 300)
            let started = Date()
            let data = try await HTTP.jsonData(request)
            let calls = ToolRouter.toolCalls(from: data)
            report.add("WERKZEUG", "calls=\(calls.count) "
                       + "namen=\(calls.map(\.name).joined(separator: ",")) "
                       + "argumente=\(TextLine.oneLine(calls.first?.arguments ?? "", limit: 140)) "
                       + "ms=\(milliseconds(since: started))")
        } catch {
            report.addFailure("WERKZEUG", error)
        }
    }

    private static func router(_ report: SweepReport, model: String, settings: AppSettings) async {
        let ask = RouterAsk(baseURL: LocalEndpoint.baseURL, key: "", model: model,
                            text: "Trag morgen um 14 Uhr einen Zahnarzttermin ein.",
                            context: SendContext(), history: [],
                            thinking: settings.thinkingOffDirective(for: model), compact: true)
        let started = Date()
        let plan = await ToolRouter.plan(ask)
        let steps = plan.actions.map { $0.stepKind.rawValue }
        report.add("ROUTER", "schritte=\(steps.joined(separator: ",")) "
                   + "anzahl=\(plan.actions.count) ms=\(milliseconds(since: started))")
    }

    private static func thinking(_ report: SweepReport, model: String) async {
        let request = LocalChatRequest(model: model,
                                       messages: [LocalMessage(role: .user,
                                                               text: "Was ist 17 mal 23? Antworte kurz.")],
                                       tools: [], maxTokens: 1024,
                                       thinking: true, temperature: 0)
        let started = Date()
        do {
            let result = try await LocalEngine.shared.run(request)
            let leaked = result.text.contains("<|channel>") || result.text.contains("<channel|>")
                || result.text.contains("<think>") || result.text.contains("</think>")
            report.add("DENKEN", "text=\(TextLine.oneLine(result.text, limit: 160)) "
                       + "channel=\(leaked) ms=\(milliseconds(since: started))")
        } catch {
            report.addFailure("DENKEN", error)
        }
    }

    private static func vision(_ report: SweepReport, model: String) async {
        do {
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 120,
                "stream": false,
                "messages": [[
                    "role": "user",
                    "content": [ChatPayload.image(url: VisionProbe.imageDataURL),
                                ChatPayload.text("Was ist auf dem Bild?")],
                ]],
            ]
            let request = try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(LocalEndpoint.baseURL),
                                            key: "", body: body, timeout: 300)
            let started = Date()
            let data = try await HTTP.jsonData(request)
            let answer = try? JSONDecoder().decode(ChatResponse.self, from: data).answerText
            report.add("BILD", "text=\(TextLine.oneLine(answer ?? "", limit: 160)) "
                       + "ms=\(milliseconds(since: started))")
        } catch {
            report.addFailure("BILD", error)
        }
    }

    private static func milliseconds(since start: Date, to end: Date = Date()) -> Int {
        Int(end.timeIntervalSince(start) * 1000)
    }
}
#endif
