import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let policy: ZoomPolicy

    init(image: UIImage, policy: ZoomPolicy = .viewer) {
        self.image = image
        self.policy = policy
    }

    func makeUIView(context: Context) -> ImageZoomScrollView {
        ImageZoomScrollView(image: image, policy: policy)
    }

    func updateUIView(_ uiView: ImageZoomScrollView, context: Context) {
        uiView.apply(image: image)
    }
}
