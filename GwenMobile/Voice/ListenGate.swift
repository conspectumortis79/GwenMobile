import Foundation

struct ListenGate: Equatable {
    var enabled: Bool
    var configured: Bool
    var foreground: Bool
    var microphoneLive: Bool
    var working: Bool
    var speaking: Bool
    var sheetOpen: Bool
    var conversation: Bool = false
    var bargeIn: Bool = true

    var holdsMicrophone: Bool { enabled && configured }
    private var canHear: Bool {
        holdsMicrophone && (foreground || microphoneLive) && !sheetOpen
    }
    var mayListen: Bool {
        canHear && (conversation ? (bargeIn || !speaking) : (!working && !speaking))
    }
    var mayCancel: Bool {
        canHear && !conversation && (working || speaking)
    }
    var keepsScreenAwake: Bool { enabled && foreground }
}
