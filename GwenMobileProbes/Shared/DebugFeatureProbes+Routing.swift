@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    static func toolProbe(_ view: ChatView) async {
        let report = SweepReport(file: "tool_probe.txt")
        let baseURL = view.settings.baseURL
        let key = view.settings.apiKey
        let model = view.settings.chatModel
        let thinkingOff = view.settings.thinkingOffDirective(for: model).bodyEntries
        report.add("KONFIG", "modell=\(model) basis=\(baseURL) "
                   + "denken_aus=\(thinkingOff.keys.sorted().joined(separator: ",").nilIfEmpty ?? "keine_steuerung")")
        for (label, choice, extra) in [("auto", "auto" as Any, thinkingOff), ("required", "required" as Any, thinkingOff),
                                       ("none", "none" as Any, thinkingOff),
                                       ("required_mit_denken", "required" as Any, [String: Any]())] {
            let started = ContinuousClock.now
            do {
                let req = try ToolCapabilityProbe.request(baseURL: baseURL, key: key, model: model,
                                                          toolChoice: choice, extra: extra)
                let (data, resp) = try await HTTP.data(req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let outcome = ToolCapabilityProbe.outcome(data: data, status: status)
                let ms = msOf(started.duration(to: .now))
                switch outcome {
                case .rejected(let code, let message):
                    report.add("WAHL_\(label)", "status=\(code) ms=\(ms) FEHLER=\(TextLine.oneLine(message, limit: 160))")
                case .acceptedWithoutCall(let text):
                    report.add("WAHL_\(label)", "status=\(status) ms=\(ms) tool_calls=nein "
                               + "\(ToolRouter.answerShape(of: data)) "
                               + "denken_zeichen=\(ToolCapabilityProbe.reasoningCharacters(in: data)) "
                               + "text=\(TextLine.oneLine(text, limit: 160))")
                case .called(let calls):
                    let first = calls.first.map { "name=\($0.name) argumente=\(TextLine.oneLine($0.arguments, limit: 160)) gültig=\($0.parsedArguments != nil)" }
                    report.add("WAHL_\(label)", "status=\(status) ms=\(ms) calls=\(calls.count) \(first ?? "-")")
                    if label == "auto", let call = calls.first {
                        await echoStep(report, baseURL: baseURL, key: key, model: model, call: call,
                                       extra: thinkingOff)
                    }
                }
            } catch {
                report.add("WAHL_\(label)", "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160)) "
                           + "ms=\(msOf(started.duration(to: .now)))")
            }
        }

        let dated = ContinuousClock.now
        do {
            let req = try ToolCapabilityProbe.request(baseURL: baseURL, key: key, model: model,
                                                      withDate: true, extra: thinkingOff)
            let (data, resp) = try await HTTP.data(req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            report.add("WAHL_auto_mit_datum", "status=\(status) ms=\(msOf(dated.duration(to: .now))) "
                       + "ergebnis=\(ToolCapabilityProbe.outcome(data: data, status: status).summary)")
        } catch {
            report.add("WAHL_auto_mit_datum", "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))")
        }

        let parallel = ContinuousClock.now
        do {
            let req = try ToolCapabilityProbe.request(baseURL: baseURL, key: key, model: model,
                                                      withDate: true,
                                                      extra: thinkingOff.merging(["parallel_tool_calls": true]) { _, new in new })
            let (data, resp) = try await HTTP.data(req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            report.add("PARALLEL_MIT_DATUM", "status=\(status) ms=\(msOf(parallel.duration(to: .now))) "
                       + "ergebnis=\(ToolCapabilityProbe.outcome(data: data, status: status).summary)")
        } catch {
            report.add("PARALLEL_MIT_DATUM", "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))")
        }

        for (label, extra) in [("ERZWUNGEN_OHNE_DENKEN", ["enable_thinking": false] as [String: Any]),
                               ("ERZWUNGEN_REASONING_NONE", ["reasoning_effort": "none"] as [String: Any])] {
            let started = ContinuousClock.now
            do {
                let req = try ToolCapabilityProbe.request(baseURL: baseURL, key: key, model: model,
                                                          toolChoice: "required", withDate: true,
                                                          extra: extra)
                let (data, resp) = try await HTTP.data(req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                report.add(label, "status=\(status) ms=\(msOf(started.duration(to: .now))) "
                           + "ergebnis=\(ToolCapabilityProbe.outcome(data: data, status: status).summary)")
            } catch {
                report.add(label, "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))")
            }
        }

        let streamed = ContinuousClock.now
        do {
            let req = try ToolCapabilityProbe.request(baseURL: baseURL, key: key, model: model, stream: true,
                                                      extra: thinkingOff)
            let lines = try await Offload.run {
                var collected: [String] = []
                let (bytes, _) = try await HTTP.session.bytes(for: req)
                for try await line in bytes.lines {
                    collected.append(line)
                    if collected.count > 400 { break }
                }
                return collected
            }
            report.add("STREAM", "zeilen=\(lines.count) ms=\(msOf(streamed.duration(to: .now))) "
                       + "tool_calls_in_deltas=\(ToolCapabilityProbe.streamCarriesToolCalls(lines))")
        } catch {
            report.add("STREAM", "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160)) "
                       + "ms=\(msOf(streamed.duration(to: .now)))")
        }

        flowLog.info("TOOLPROBE fertig")
    }

    static func echoStep(_ report: SweepReport, baseURL: String, key: String,
                         model: String, call: ToolCall, extra: [String: Any]) async {
        let started = ContinuousClock.now
        do {
            let req = try ToolCapabilityProbe.echoRequest(baseURL: baseURL, key: key, model: model, call: call,
                                                          extra: extra)
            let (data, resp) = try await HTTP.data(req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            report.add("RÜCKGABE", "status=\(status) ms=\(msOf(started.duration(to: .now))) "
                       + "ergebnis=\(ToolCapabilityProbe.outcome(data: data, status: status).summary)")
        } catch {
            report.add("RÜCKGABE", "ausnahmefehler=\(TextLine.oneLine(error.localizedDescription, limit: 160))")
        }
    }

}
#endif
