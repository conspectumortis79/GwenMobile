@testable import GwenMobileFeatureCore
import GwenMobileKit
import MessageUI
import UIKit

@MainActor
final class ComposeMessageSender: NSObject, MessageSending, MFMessageComposeViewControllerDelegate {
    private let canSend: @MainActor () -> Bool
    private let isActive: @MainActor () -> Bool
    private let host: @MainActor () -> UIViewController?
    private var pending: CheckedContinuation<MessageSendResult, Never>?
    private var sheet: MFMessageComposeViewController?
    private var timeout: Task<Void, Never>?

    private static let timeoutDuration = Duration.seconds(180)

    init(canSend: @escaping @MainActor () -> Bool = { MFMessageComposeViewController.canSendText() },
         isActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         host: @escaping @MainActor () -> UIViewController? = { Presenter.topViewController }) {
        self.canSend = canSend
        self.isActive = isActive
        self.host = host
    }

    var way: String { "nachrichtenformular" }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        guard canSend() else { return .unavailable }
        guard pending == nil, isActive(), let host = host() else { return .needsForeground }
        let sheet = MFMessageComposeViewController()
        sheet.recipients = [number.digits]
        sheet.body = text
        sheet.messageComposeDelegate = self
        self.sheet = sheet
        return await withCheckedContinuation { (done: CheckedContinuation<MessageSendResult, Never>) in
            pending = done
            armTimeout()
            host.present(sheet, animated: true)
        }
    }

    nonisolated static func result(of outcome: MessageComposeResult) -> MessageSendResult {
        switch outcome {
        case .sent: return .sent(direct: false)
        case .cancelled: return .cancelled
        case .failed: return .failed(L.t("message_compose_failed"))
        @unknown default: return .failed(L.t("message_compose_failed"))
        }
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                  didFinishWith result: MessageComposeResult) {
        let outcome = Self.result(of: result)
        Task { @MainActor in self.finish(outcome) }
    }

    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.timeoutDuration)
            guard let self, !Task.isCancelled, self.pending != nil else { return }
            self.finish(.failed(L.t("message_compose_failed")))
        }
    }

    private func finish(_ outcome: MessageSendResult) {
        timeout?.cancel()
        timeout = nil
        sheet?.dismiss(animated: true)
        sheet = nil
        let waiting = pending
        pending = nil
        waiting?.resume(returning: outcome)
    }
}
