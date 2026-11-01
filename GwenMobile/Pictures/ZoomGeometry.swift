import CoreGraphics

struct ZoomPolicy: Equatable, Sendable {
    var detailFactor: CGFloat
    var maxFactor: CGFloat

    static let viewer = ZoomPolicy(detailFactor: 2.5, maxFactor: 6)
}

struct ZoomGeometry: Equatable, Sendable {
    let fitScale: CGFloat
    let detailScale: CGFloat
    let maxScale: CGFloat

    init(container: CGSize, image: CGSize, policy: ZoomPolicy) {
        let fit = Self.fitScale(container: container, image: image)
        self.fitScale = fit
        self.detailScale = fit * policy.detailFactor
        self.maxScale = fit * max(policy.maxFactor, policy.detailFactor)
    }

    static func fitScale(container: CGSize, image: CGSize) -> CGFloat {
        guard container.width > 0, container.height > 0, image.width > 0, image.height > 0 else {
            return 1
        }
        return min(container.width / image.width, container.height / image.height)
    }

    func scaleAfterDoubleTap(current: CGFloat) -> CGFloat {
        current >= detailScale - 0.01 ? fitScale : detailScale
    }
}

enum ZoomCentering {
    static func offset(containerExtent: CGFloat, contentExtent: CGFloat) -> CGFloat {
        max(containerExtent - contentExtent, 0) / 2
    }
}
