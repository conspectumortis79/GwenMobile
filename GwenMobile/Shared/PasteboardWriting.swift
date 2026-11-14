import GwenMobileKit
import UIKit

@MainActor
protocol PasteboardWriting {
    func write(_ text: String)
}

@MainActor
struct SystemPasteboard: PasteboardWriting {
    func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}
