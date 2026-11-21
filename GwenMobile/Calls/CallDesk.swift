import Foundation

@MainActor
final class CallDesk: ObservableObject {
    private(set) var directory: any ContactDirectory
    private(set) var dialer: any CallPlacing
    #if DEBUG
    private var dialerStandIn = DeskStandIn<any CallPlacing>()
    private var directoryStandIn = DeskStandIn<any ContactDirectory>()
    #endif

    init(directory: any ContactDirectory = LiveContactDirectory(),
         dialer: (any CallPlacing)? = nil) {
        self.directory = directory
        self.dialer = dialer ?? DialerChoice.dialer(for: DialerChoice.current())
    }

    func runner() -> CallFlowRunner {
        CallFlowRunner(directory: directory, dialer: dialer)
    }

    #if DEBUG
    func stand(in dialer: any CallPlacing, directory: (any ContactDirectory)? = nil) {
        dialerStandIn.stand(dialer, over: &self.dialer)
        if let directory { directoryStandIn.stand(directory, over: &self.directory) }
    }

    func restore() {
        dialerStandIn.restore(&dialer)
        directoryStandIn.restore(&directory)
    }
    #endif
}
