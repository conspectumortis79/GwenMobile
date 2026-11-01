@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation

enum ChatThreadRow: Identifiable {
    case day(Date)
    case message(ChatMessage)

    var id: String {
        switch self {
            case .day(let date): return "day-\(date.timeIntervalSince1970)"
            case .message(let message): return ChatScrollAnchors.message(message.id)
        }
    }

    static func grouped(_ messages: [ChatMessage], in calendar: Calendar = Calendar.current) -> [ChatThreadRow] {
        var rows: [ChatThreadRow] = []
        rows.reserveCapacity(messages.count * 2)
        for (index, message) in messages.enumerated() {
            if index == 0 || !calendar.isDate(message.date, inSameDayAs: messages[index - 1].date) {
                rows.append(.day(message.date))
            }
            rows.append(.message(message))
        }
        return rows
    }
}

enum ChatThreadStatusRow: Identifiable {
    case streaming(text: String)
    case transcribing(text: String)
    case processing(text: String)
    case researching(text: String)

    var id: String {
        switch self {
            case .streaming: return ChatScrollAnchors.streaming
            case .transcribing: return ChatScrollAnchors.asrWorking
            case .processing: return ChatScrollAnchors.imageWorking
            case .researching: return ChatScrollAnchors.webStatus
        }
    }

    static func present(streaming: String?, transcribing: String?,
                        processing: String?, researching: String?) -> [ChatThreadStatusRow] {
        [streaming.map { ChatThreadStatusRow.streaming(text: $0) },
         transcribing.map { ChatThreadStatusRow.transcribing(text: $0) },
         processing.map { ChatThreadStatusRow.processing(text: $0) },
         researching.map { ChatThreadStatusRow.researching(text: $0) }].compactMap { $0 }
    }
}
