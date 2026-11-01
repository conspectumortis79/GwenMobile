@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit
#if targetEnvironment(macCatalyst)
import ServiceManagement
import SwiftUI
#endif

@MainActor
enum DebugMacPartsProbe {
    static func run(_: ChatView) async {
        let report = SweepReport(file: "mac_parts.txt")
        #if targetEnvironment(macCatalyst)
        loginItem(report)
        await help(report)
        windowStyle(report)
        await notifications(report)
        await drop(report)
        #else
        report.add("PLATTFORM", "nur_mac nicht_verfuegbar_auf=ios")
        #endif
        flowLog.info("MACPARTS fertig")
    }

    #if targetEnvironment(macCatalyst)
    private static func loginItem(_ report: SweepReport) {
        let inApplications = Bundle.main.bundlePath.hasPrefix("/Applications/")
        report.add("AUTOSTART", "aktiv=\(MacLoginItem.isEnabled) "
                   + "status=\(SMAppService.mainApp.status.rawValue) "
                   + "in_Programmen=\(inApplications) aktion=schreibzugriff_uebersprungen")
    }

    private static func help(_ report: SweepReport) async {
        let before = MacHelpRequests.shared.token
        MacHelpRequests.shared.open()
        let opened = await ProbeWait.until(2) { MacHelpRequests.shared.token > before }
        var screenshot = "kein_fenster"
        if let window = ProbeHosting.host(MacHelpView()) {
            screenshot = await ProbeHosting.settledSnapshot(window, "mac_help.jpg")
            ProbeHosting.close(window)
        }
        report.add("HILFE", "abschnitte=\(MacHelpView.sectionKeys.count) menue=\(opened) "
                   + "token=\(MacHelpRequests.shared.token - before) screenshot=\(screenshot)")
    }

    private static func windowStyle(_ report: SweepReport) {
        let windows = WindowStyleSync.sceneWindows()
        guard !windows.isEmpty else {
            report.add("FENSTERSTIL", "keine_fenster")
            return
        }
        let before = windows.map(\.overrideUserInterfaceStyle)
        WindowStyleSync.apply(.dark, to: windows)
        let dark = windows.allSatisfy { $0.overrideUserInterfaceStyle == .dark }
        WindowStyleSync.apply(.unspecified, to: windows)
        let reset = windows.allSatisfy { $0.overrideUserInterfaceStyle == .unspecified }
        for (window, style) in zip(windows, before) { window.overrideUserInterfaceStyle = style }
        let restored = zip(windows, before).allSatisfy { $0.overrideUserInterfaceStyle == $1 }
        report.add("FENSTERSTIL", "fenster=\(windows.count) dunkel=\(dark) neutral=\(reset) "
                   + "wiederhergestellt=\(restored)")
    }

    private static func notifications(_ report: SweepReport) async {
        let center = UNUserNotificationCenter.current()
        let installed = center.delegate === NotificationPresenter.shared
        var line: String?
        NotificationPermission.request(reporting: "PROBE", ask: { true }, report: { line = $0 })
        let reported = await ProbeWait.until(2) { line != nil }
        report.add("MITTEILUNGEN", "delegate_installiert=\(installed) "
                   + "delegate=\(center.delegate.map { String(describing: type(of: $0)) } ?? "keins") "
                   + "abfrage_gemeldet=\(reported) zeile=\(line ?? "-")")
    }

    private static func drop(_ report: SweepReport) async {
        let kinds = ["probe.pdf", "probe.docx", "probe.png", "probe.md", "probe.xyz"]
        let policy = kinds.map { "\($0)=\(itemName(DropPolicy.item(forFileNamed: $0)))" }
        guard let window = ProbeHosting.host(Text("Drop").macFileDrop { _ in }) else {
            report.add("DROP", "kein_fenster")
            return
        }
        let attached = await ProbeWait.until(3) {
            window.interactions.contains { $0 is UIDropInteraction }
        }
        report.add("DROP", "verknuepft=\(attached) interaktionen=\(window.interactions.count) "
                   + "policy=\(policy.joined(separator: " "))")
        ProbeHosting.close(window)
    }

    private static func itemName(_ item: DroppedItem?) -> String {
        switch item {
        case .picture: return "bild"
        case .document(let kind): return kind.rawValue
        case nil: return "-"
        }
    }
    #endif
}
#endif
