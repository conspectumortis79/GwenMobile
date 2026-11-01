import SwiftUI
import GwenMobileDevice
#if DEBUG
import GwenMobileProbes
#endif

@main
enum GwenMobileShell {
    @MainActor static func main() {
        #if DEBUG
        GwenMobileProbeBootstrap.install()
        #endif
        installSystemsIfNeeded()
        GwenMobileApp.main()
    }

    @MainActor static func installSystemsIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["XCTestConfigurationFilePath"] == nil else { return }
        DeviceSystems.install()
    }
}
