@testable import GwenMobileFeatureCore
import GwenMobileKit
import EventKit
import EventKitUI
import SwiftUI
import UIKit

@MainActor
struct CalendarEventView: UIViewControllerRepresentable {
    let ref: CalendarRef
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> CalendarEventHost {
        CalendarEventHost(event: CalendarService.event(for: ref),
                          closeTitle: L.t("done"),
                          fallbackText: L.t("cal_chip_gone"),
                          onDismiss: onDismiss)
    }

    func updateUIViewController(_ controller: CalendarEventHost, context: Context) {
        controller.setOnDismiss(onDismiss)
    }
}

@MainActor
final class CalendarEventHost: UINavigationController, EKEventViewDelegate {
    private let closesWithoutEvent: Bool
    private var closer: () -> Void
    private let closeTitle: String
    private var closing = false

    init(event: EKEvent?, closeTitle: String, fallbackText: String, onDismiss: @escaping () -> Void) {
        self.closer = onDismiss
        self.closeTitle = closeTitle
        self.closesWithoutEvent = event == nil
        super.init(rootViewController: Self.root(event: event, fallbackText: fallbackText))
        (topViewController as? EKEventViewController)?.delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let detail = topViewController as? EKEventViewController else { return }
        if detail.navigationItem.leftBarButtonItem == nil {
            detail.navigationItem.leftBarButtonItem = UIBarButtonItem(title: closeTitle, style: .prominent,
                                                                     target: self, action: #selector(closeTapped))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if closesWithoutEvent { close() }
    }

    func setOnDismiss(_ onDismiss: @escaping () -> Void) { closer = onDismiss }

    @objc private func closeTapped() { close() }

    private func close() {
        guard !closing else { return }
        closing = true
        closer()
    }

    private static func root(event: EKEvent?, fallbackText: String) -> UIViewController {
        guard let event else { return Self.fallback(fallbackText) }
        let detail = EKEventViewController()
        detail.event = event
        detail.allowsEditing = true
        detail.allowsCalendarPreview = true
        return detail
    }

    private static func fallback(_ text: String) -> UIViewController {
        let controller = UIViewController()
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: controller.view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: controller.view.trailingAnchor, constant: -24)
        ])
        return controller
    }

    nonisolated func eventViewController(_ controller: EKEventViewController,
                                         didCompleteWith action: EKEventViewAction) {
        Task { @MainActor in self.close() }
    }
}
