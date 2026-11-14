#if DEBUG
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit

public enum GwenMobileProbeBootstrap {
    @MainActor public static func install() {
        ProbeHook.start = { view in view.startFlowTest() }
        ProbeHook.dispatch = { view, name in view.dispatchFlowTest(name) }
        ProbeHook.attachScrollProxy = { view, proxy in view.attachScrollProxy(proxy) }
        ProbeHook.installTouchLog = { ChipTouchLog.install() }
    }
}
#endif
#endif
