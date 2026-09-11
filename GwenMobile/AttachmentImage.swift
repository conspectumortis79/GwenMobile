import SwiftUI
import UIKit

struct AttachmentImage: View {
    let att: Attachment
    var fit: Bool = false
    @EnvironmentObject private var feed: ImageFeed

    var body: some View {
        #if DEBUG
        let _ = RenderStats.attachmentBody.bump()
        #endif
        let rendition = feed.rendition(for: att.file)
        let size = Self.size(ratio: rendition?.ratio ?? 1, fit: fit)
        Group {
            if let rendition {
                Image(uiImage: rendition.image).resizable()
            } else {
                Color(.systemGray5)
            }
        }
        .scaledToFill()
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: fit ? 16 : 14))
        .onAppear {
            #if DEBUG
            RenderStats.attachmentTask.bump()
            #endif
            feed.load(att.file)
        }
    }

    static func size(ratio: CGFloat, fit: Bool) -> CGSize {
        let r = max(0.01, ratio)
        return fit
            ? CGSize(width: 300, height: min(420, 300 / r))
            : CGSize(width: min(200, 200 * r), height: min(200, 200 / r))
    }
}
