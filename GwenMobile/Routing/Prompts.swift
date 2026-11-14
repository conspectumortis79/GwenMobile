import GwenMobileKit
import Foundation

enum PromptToken {
    static var fields: [String: String] { PromptLibrary.fields("prompt_tokens") }

    static var picture: String { fields["picture"] ?? "" }
    static var context: String { fields["context"] ?? "" }
    static var newQuestion: String { fields["new_question"] ?? "" }
}

enum Prompt {
    enum Router {
        static func calendar(tz: String, now: String, events: String,
                              calendars: String, history: String, planned: String = "") -> String {
            var context = ""
            if !planned.isEmpty {
                context += "\n" + PromptLibrary.text("calendar_router_planned") + "\n\(planned)\n"
            }
            if !events.isEmpty {
                context += "\n" + PromptLibrary.text("calendar_router_events") + "\n\(events)\n"
            }
            if !calendars.isEmpty {
                context += calendars
            }
            if !history.isEmpty {
                context += "\n" + PromptLibrary.text("calendar_router_history") + "\n\(history)\n"
            }
            return PromptLibrary.text("calendar_router", ["now": now, "tz": tz, "context": context,
                                                          "relative_days": PromptLibrary.text("router_relative_days")])
        }
    }

    enum Product {
        static func finding() -> String {
            PromptLibrary.text("product_finding", ["product_tool": ToolRouter.productTool])
        }
    }

    enum Price {
        static func offers() -> String {
            PromptLibrary.text("price_offers")
        }

        static func watch() -> String {
            PromptLibrary.text("price_watch", ["report_tool": LivePriceWatchChecker.reportTool])
        }
    }

    enum Research {
        static func webAnswer(length: AnswerLength = .compact, sourceNote: String = "") -> String {
            PromptLibrary.text("research_answer", ["length_instruction": answerLength(length),
                                                   "source_note": sourceNote])
        }

        static func answerLength(_ length: AnswerLength) -> String {
            guard length.isDetailed else {
                return PromptLibrary.text("research_length_compact", ["words": String(length.words)])
            }
            var items = ""
            if let each = length.wordsEach {
                items = PromptLibrary.text("research_length_deep_items",
                                           ["items": String(length.items), "each": String(each)])
            }
            return PromptLibrary.text("research_length_deep",
                                      ["words": String(length.words), "items_clause": items])
        }

        static func followUpQuery() -> String {
            PromptLibrary.text("research_followup", ["context_token": PromptToken.context,
                                                     "new_question_token": PromptToken.newQuestion,
                                                     "picture_attached":
                                                        ConversationTranscript.Picture.attached.rawValue,
                                                     "picture_generated":
                                                        ConversationTranscript.Picture.generated.rawValue,
                                                     "tool": ToolRouter.resolveQueryTool,
                                                     "resolved": StructuredToolStatus.resolved.rawValue,
                                                     "unresolved": StructuredToolStatus.unresolved.rawValue])
        }

        static func imagePrompt(pictures: Int) -> String {
            var text = PromptLibrary.text("image_prompt_writer",
                                          ["context_token": PromptToken.context,
                                           "new_question_token": PromptToken.newQuestion,
                                           "tool": ToolRouter.composeImagePromptTool,
                                           "resolved": StructuredToolStatus.resolved.rawValue,
                                           "unresolved": StructuredToolStatus.unresolved.rawValue])
            guard pictures > 1 else { return text }
            text += "\n" + PromptLibrary.text("image_prompt_writer_multi",
                                              ["pictures": String(pictures)])
            return text
        }
    }

    enum Pictures {
        static func director(pictures count: Int) -> String {
            PromptLibrary.text("picture_director", ["picture_token": PromptToken.picture,
                                                    "count": String(count)])
        }
    }
}
