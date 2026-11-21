#if DEBUG
@testable import GwenMobileFeatureCore
import Foundation

public enum GwenMobileProbeBootstrap {
    @MainActor public static func install() {
        if ProcessInfo.processInfo.environment["GWEN_PROBE_AUTO_PERMISSIONS"] == "1" {
            NotificationPermission.askOverride = { true }
            NotificationTimer.requestPermission = { true }
            #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
            AlarmKitTimer.requestPermission = { .authorized }
            #endif
        }
        ProbeHook.start = { view in view.startFlowTest() }
        ProbeHook.dispatch = { view, name in view.dispatchFlowTest(name) }
        ProbeHook.attachScrollProxy = { view, proxy in view.attachScrollProxy(proxy) }
        ProbeHook.installTouchLog = { ChipTouchLog.install() }
    }
}
#endif
