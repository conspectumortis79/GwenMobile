import Foundation

struct AnswerAnnouncement: Equatable {
    let speaks: Bool
    let notifies: Bool

    static func plan(readAloud: Bool, foreground: Bool, listening: Bool) -> AnswerAnnouncement {
        let away = listening && !foreground
        return AnswerAnnouncement(speaks: readAloud || away, notifies: away)
    }
}
