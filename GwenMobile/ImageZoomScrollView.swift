import UIKit

final class ImageZoomScrollView: UIScrollView {
    private let imageView = UIImageView()
    private let policy: ZoomPolicy
    private var naturalSize = CGSize.zero
    private var geometry = ZoomGeometry(container: .zero, image: .zero, policy: .viewer)
    private var appliedContainerSize = CGSize.zero

    init(image: UIImage, policy: ZoomPolicy = .viewer) {
        self.policy = policy
        super.init(frame: .zero)
        delegate = self
        clipsToBounds = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        applySize(of: image)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { return nil }

    func apply(image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        appliedContainerSize = .zero
        zoomScale = 1
        applySize(of: image)
    }

    private func applySize(of image: UIImage) {
        naturalSize = image.size
        imageView.frame = CGRect(origin: .zero, size: naturalSize)
        contentSize = naturalSize
        geometry = ZoomGeometry(container: .zero, image: naturalSize, policy: policy)
        setNeedsLayout()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        handleDoubleTap(at: gesture.location(in: self), animated: true)
    }

    func handleDoubleTap(at point: CGPoint, animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let target = geometry.scaleAfterDoubleTap(current: zoomScale)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        let anchor = imageView.convert(point, from: self)
        let origin = CGPoint(x: min(max(anchor.x - size.width / 2, 0), max(naturalSize.width - size.width, 0)),
                             y: min(max(anchor.y - size.height / 2, 0), max(naturalSize.height - size.height, 0)))
        zoom(to: CGRect(origin: origin, size: size), animated: animated)
        if !animated { centerContents() }
    }

    private func applyFitIfNeeded() {
        guard bounds.width > 0, bounds.height > 0, bounds.size != appliedContainerSize,
              naturalSize.width > 0, naturalSize.height > 0 else { return }
        appliedContainerSize = bounds.size
        geometry = ZoomGeometry(container: bounds.size, image: naturalSize, policy: policy)
        minimumZoomScale = geometry.fitScale
        maximumZoomScale = geometry.maxScale
        zoomScale = geometry.fitScale
    }

    private func centerContents() {
        guard !isDragging, !isZooming, naturalSize.width > 0, naturalSize.height > 0 else { return }
        let width = naturalSize.width * zoomScale
        let height = naturalSize.height * zoomScale
        var origin = imageView.frame.origin
        origin.x = ZoomCentering.offset(containerExtent: bounds.width, contentExtent: width)
        origin.y = ZoomCentering.offset(containerExtent: bounds.height, contentExtent: height)
        if imageView.frame.origin != origin { imageView.frame.origin = origin }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFitIfNeeded()
        centerContents()
    }
}

extension ImageZoomScrollView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContents() }
}
