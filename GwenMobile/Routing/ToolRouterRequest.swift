import GwenMobileKit
import Foundation

extension ToolRouter {
    static func systemBlock(now: String, context: SendContext, transcript: String,
                            catalog: String = "", eraseHistoryWord: String = "",
                            document: String = "", watchCatalog: String = "") -> String {
        var values = promptValues
        values["now"] = now
        values["relative_days"] = PromptLibrary.text("router_relative_days")
        var text = PromptLibrary.text("router_base_before", values)
            + (context.textNeedsTheModel ? PromptLibrary.text("router_translation_rule_media", values)
                                         : PromptLibrary.text("router_translation_rule_device", values))
            + PromptLibrary.text("router_base_after", values)
        if context.attachedVideo {
            text += PromptLibrary.text("router_video_attached", values)
        }
        if context.attachedImage {
            text += PromptLibrary.text("router_picture_attached", values)
        } else if context.rememberedImage {
            text += PromptLibrary.text("router_picture_remembered", values)
        }
        if context.attachedFile {
            text += PromptLibrary.text("router_file", values)
        }
        if context.scannedDocument {
            text += PromptLibrary.text("router_scan", values)
            if context.documentReminder {
                text += PromptLibrary.text("router_scan_reminder", values)
            }
        }
        text += PromptLibrary.text("router_memory", values)
        text += PromptLibrary.text("router_history", values)
        text += PromptLibrary.text("router_weather", values)
        text += PromptLibrary.text("router_scan_tool", values)
        text += PromptLibrary.text("router_video", values)
        if !eraseHistoryWord.isEmpty {
            text += PromptLibrary.text("router_erase_word", ["erase_history_word": eraseHistoryWord])
        }
        if !catalog.isEmpty {
            text += PromptLibrary.text("router_catalog", ["catalog": catalog])
        }
        if !watchCatalog.isEmpty {
            text += PromptLibrary.text("router_watch_catalog", ["watch_catalog": watchCatalog])
        }
        if context.scannedDocument, !document.isEmpty {
            text += PromptLibrary.text("router_document", ["document": document])
        }
        if !transcript.isEmpty {
            text += PromptLibrary.text("router_transcript", ["transcript": transcript])
        }
        return text
    }

    static func toolFields(maxTokens: Int, tools: [[String: Any]],
                           toolChoice: Any = "auto", parallel: Bool = false) -> [String: Any] {
        var fields: [String: Any] = ["max_tokens": maxTokens, "tools": tools]
        if let name = toolChoice as? String {
            if name != automaticChoice { fields["tool_choice"] = name }
        } else {
            fields["tool_choice"] = toolChoice
        }
        return fields
    }

    #if DEBUG
    static func toolRequestBody(model: String, maxTokens: Int, stream: Bool,
                                messages: [[String: Any]], tools: [[String: Any]],
                                toolChoice: Any = "auto") -> [String: Any] {
        var body: [String: Any] = ["model": model, "stream": stream, "messages": messages]
        for (key, value) in toolFields(maxTokens: maxTokens, tools: tools, toolChoice: toolChoice) {
            body[key] = value
        }
        return body
    }
    #endif

    static func request(baseURL: String, key: String, model: String, text: String,
                        system: String, attachable: Bool, translatesOnDevice: Bool = true,
                        picture: Data? = nil, pictures: [Data] = [], parallel: Bool = false,
                        maxTokens budget: Int = maxTokens,
                        toolChoice: Any = automaticChoice, compact: Bool = false,
                        thinking: ThinkingDirective) throws -> URLRequest {
        let sent = (picture.map { [$0] } ?? []) + pictures
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(system),
                                        ChatPayload.user(userContent(text: text, pictures: sent))],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             extra: toolFields(maxTokens: budget,
                                               tools: tools(attachable: attachable,
                                                            translatesOnDevice: translatesOnDevice,
                                                            compact: compact),
                                               toolChoice: toolChoice, parallel: parallel))
    }

    static func userContent(text: String, pictures: [Data]) -> Any {
        let images = pictures.compactMap { ChatPayload.image($0) }
        guard !images.isEmpty else { return text }
        return [ChatPayload.text(text)] + images
    }
}
