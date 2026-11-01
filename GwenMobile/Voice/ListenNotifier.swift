import GwenMobileKit
import Foundation
import UserNotifications

@MainActor
protocol ListenNotifying {
    func prepare()
    func listeningStopped()
    func answered(_ text: String)
}

struct ListenNotice: Equatable, Sendable {
    static let stoppedID = "listen.stopped"
    static let answerLimit = 400

    let id: String
    let body: String
    let audible: Bool

    static var stopped: ListenNotice {
        ListenNotice(id: stoppedID, body: L.t("listen_stopped_notice"), audible: true)
    }

    @MainActor
    static func answer(_ text: String, id: String = UUID().uuidString) -> ListenNotice? {
        let spoken = SpeechSynthesizer.stripForSpeech(text)
        guard !spoken.isEmpty else { return nil }
        return ListenNotice(id: id, body: TextLine.oneLine(spoken, limit: answerLimit), audible: false)
    }
}

@MainActor
struct LocalListenNotifier: ListenNotifying {
    func prepare() {
        NotificationPermission.request(reporting: "MITTEILUNG erlaubt")
    }

    func listeningStopped() {
        post(.stopped)
    }

    func answered(_ text: String) {
        guard let notice = ListenNotice.answer(text) else { return }
        post(notice)
    }

    private func post(_ notice: ListenNotice) {
        let content = UNMutableNotificationContent()
        content.body = notice.body
        if notice.audible { content.sound = .default }
        let request = UNNotificationRequest(identifier: notice.id, content: content, trigger: nil)
        let kind = notice.id == ListenNotice.stoppedID ? "zuhoeren_beendet" : "antwort"
        UNUserNotificationCenter.current().add(request) { error in
            flowMark("MITTEILUNG \(kind) fehler=\(error?.localizedDescription ?? "-")")
        }
    }
}
