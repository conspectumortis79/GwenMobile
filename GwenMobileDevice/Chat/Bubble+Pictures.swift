@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    func openPreview(_ att: Attachment) {
        onPreview?(att)
    }

    @ViewBuilder func imageActions(_ att: Attachment, library: Bool) -> some View {
        Button(action: TapProbe.action({ shareImage(att) })) {
            Label(L.t("send_via_airdrop"), systemImage: "paperplane")
        }
        if library {
            Button(action: TapProbe.action({ saveAttachment(att) })) {
                Label(L.t("save_to_photos"), systemImage: "square.and.arrow.down")
            }
            if let onEdit {
                Button(action: TapProbe.action({ onEdit(att) })) {
                    Label(L.t("edit_this"), systemImage: "pencil")
                }
            }
        }
    }

    func shareImage(_ att: Attachment) {
        guard let url = media?.storedURL(for: att) else {
            shareFailure = L.t("image_gone")
            return
        }
        shareStored(url)
    }

    func openPicture(_ picture: WebPicture) {
        onOpenPicture?(picture)
    }

    func openPictureSource(_ picture: WebPicture) {
        openWebAddress(picture.pageURL.isEmpty ? picture.fullURL : picture.pageURL)
    }

}
