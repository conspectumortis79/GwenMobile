import GwenMobileKit
import Foundation

extension QwenAPI {
    static func calendarPlan(baseURL: String, key: String, model: String,
                             instruction: String,
                             history: [ChatMessage] = [], events: String = "",
                             calendars: String = "",
                             planned: String = "",
                             thinking: ThinkingDirective) async throws -> CalendarPlan? {
        let offset = TimeZone.current.secondsFromGMT()
        let oh = offset / 3600, om = abs(offset % 3600 / 60)
        let tz = String(format: "UTC%@%02d:%02d", offset < 0 ? "-" : "+", abs(oh), om)
        let sys = Prompt.Router.calendar(tz: tz, now: Formatters.planNow(Date()),
                                         events: events, calendars: calendars,
                                         history: ConversationTranscript.from(messages: history),
                                         planned: planned)
        let msg = ChatMessage(role: .user, text: instruction)
        let req = try makeRequest(baseURL: baseURL, key: key, model: model,
                                  messages: [msg], imageData: [], stream: false, system: sys,
                                  thinking: thinking)
        guard let raw = try await askText(req),
              let decoded = JSONFragment.decode(CalendarPlan.self, from: raw) else { return nil }
        return decoded
    }

}
