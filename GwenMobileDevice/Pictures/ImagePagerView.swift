@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import UIKit

enum ViewerPage: Equatable {
    case loading
    case ready(UIImage)
    case unavailable
}

struct ImagePagerView: UIViewControllerRepresentable {
    let pages: [ViewerPage]
    var arrowKeys: Bool = ViewerArrowKeys.enabledOnThisPlatform
    @Binding var index: Int

    func makeUIViewController(context: Context) -> PagerHostController {
        let host = PagerHostController()
        let coordinator = context.coordinator
        host.onTurn = { seen in coordinator.turn(seen) }
        host.onStep = { step in coordinator.step(step) }
        host.arrowKeysEnabled = arrowKeys
        host.configure(pages: pages)
        host.turn(to: index, animated: false)
        return host
    }

    func updateUIViewController(_ host: PagerHostController, context: Context) {
        context.coordinator.parent = self
        host.configure(pages: pages)
        host.turn(to: index, animated: abs(host.visibleIndex - index) == 1)
    }

    func makeCoordinator() -> PagerCoordinator { PagerCoordinator(self) }
}

@MainActor
final class PagerCoordinator {
    var parent: ImagePagerView

    init(_ parent: ImagePagerView) {
        self.parent = parent
    }

    func turn(_ index: Int) {
        guard parent.index != index else { return }
        parent.index = index
    }

    func step(_ step: ViewerStep) {
        guard let next = step.target(from: parent.index, count: parent.pages.count) else { return }
        parent.index = next
    }
}

final class PagerHostController: UIViewController {
    var onTurn: ((Int) -> Void)?
    var onStep: ((ViewerStep) -> Void)?
    var arrowKeysEnabled = false

    override var keyCommands: [UIKeyCommand]? {
        guard arrowKeysEnabled else { return nil }
        return ViewerArrowKeys.commands(back: #selector(stepBackward), forward: #selector(stepForward))
    }

    override var canBecomeFirstResponder: Bool { arrowKeysEnabled }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard arrowKeysEnabled else { return }
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    @objc private func stepBackward() { onStep?(.back) }

    @objc private func stepForward() { onStep?(.forward) }

    private let pager = UIPageViewController(transitionStyle: .scroll,
                                             navigationOrientation: .horizontal,
                                             options: [UIPageViewController.OptionsKey.interPageSpacing: 12])
    private var pages: [ViewerPage] = []
    private var pagingAllowed = true

    #if DEBUG
    var pictureCount: Int { pages.count }
    #endif
    var visibleIndex: Int { (pager.viewControllers?.first as? ImagePageViewController)?.index ?? 0 }
    var isPagingEnabled: Bool { pagingAllowed && pages.count > 1 }

    override func loadView() {
        view = clearRootView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pager)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pager.view)
        NSLayoutConstraint.activate([
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.view.topAnchor.constraint(equalTo: view.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pager.didMove(toParent: self)
        pager.dataSource = self
        pager.delegate = self
    }

    func configure(pages: [ViewerPage]) {
        let countChanged = self.pages.count != pages.count
        self.pages = pages
        if countChanged { allowPaging(true) }
        refresh()
    }

    func turn(to index: Int, animated: Bool) {
        let shown = pager.viewControllers?.first as? ImagePageViewController
        guard shown?.index != index else {
            allowPaging(shown?.isZoomedIn != true)
            return
        }
        guard let controller = controller(at: index) else { return }
        let direction: UIPageViewController.NavigationDirection =
            index >= visibleIndex ? .forward : .reverse
        pager.setViewControllers([controller], direction: direction, animated: animated)
        allowPaging(true)
    }

    func refresh() {
        for case let controller as ImagePageViewController in pager.viewControllers ?? [] {
            controller.show(page(at: controller.index))
        }
    }

    func page(at index: Int) -> ViewerPage {
        pages.indices.contains(index) ? pages[index] : .unavailable
    }

    func turnCompleted(with controller: ImagePageViewController?) {
        guard let controller else { return }
        allowPaging(!controller.isZoomedIn)
        onTurn?(controller.index)
    }

    func pageBefore(_ index: Int) -> ImagePageViewController? {
        guard isPagingEnabled else { return nil }
        return controller(at: index - 1)
    }

    func pageAfter(_ index: Int) -> ImagePageViewController? {
        guard isPagingEnabled else { return nil }
        return controller(at: index + 1)
    }

    private func allowPaging(_ allowed: Bool) {
        pagingAllowed = allowed
    }

    private func controller(at index: Int) -> ImagePageViewController? {
        guard pages.indices.contains(index) else { return nil }
        let controller = ImagePageViewController(index: index)
        controller.show(pages[index])
        controller.onZoomed = { [weak self] zoomed in self?.allowPaging(!zoomed) }
        return controller
    }
}

extension PagerHostController: UIPageViewControllerDataSource {
    func pageViewController(_ pager: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? ImagePageViewController)?.index else { return nil }
        return pageBefore(index)
    }

    func pageViewController(_ pager: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? ImagePageViewController)?.index else { return nil }
        return pageAfter(index)
    }
}

extension PagerHostController: UIPageViewControllerDelegate {
    func pageViewController(_ pager: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed else { return }
        turnCompleted(with: pager.viewControllers?.first as? ImagePageViewController)
    }
}

final class ImagePageViewController: UIViewController {
    let index: Int
    var onZoomed: ((Bool) -> Void)?
    var isZoomedIn: Bool { scroll?.isZoomedIn ?? false }

    private let spinner = UIActivityIndicatorView(style: .large)
    private let notice = UILabel()
    private var scroll: ImageZoomScrollView?
    private var waiting: ViewerPage?

    init(index: Int) {
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    func show(_ page: ViewerPage) {
        guard isViewLoaded else {
            waiting = page
            return
        }
        waiting = nil
        apply(page)
    }

    override func loadView() {
        let root = clearRootView()
        spinner.color = .white
        spinner.hidesWhenStopped = true
        notice.text = L.t("image_gone")
        notice.textColor = .white
        notice.font = .systemFont(ofSize: 15, weight: .semibold)
        notice.numberOfLines = 3
        notice.textAlignment = .center
        notice.isHidden = true
        for element in [spinner, notice] {
            element.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(element)
        }
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            notice.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            notice.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 32),
            notice.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let waiting { apply(waiting) }
    }

    private func apply(_ page: ViewerPage) {
        switch page {
        case .loading:
            scroll?.isHidden = true
            notice.isHidden = true
            spinner.startAnimating()
        case .unavailable:
            scroll?.isHidden = true
            spinner.stopAnimating()
            notice.isHidden = false
        case .ready(let image):
            spinner.stopAnimating()
            notice.isHidden = true
            if let scroll {
                scroll.apply(image: image)
                scroll.isHidden = false
            } else {
                attach(image)
            }
        }
    }

    private func attach(_ image: UIImage) {
        let scroll = ImageZoomScrollView(image: image)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.onZoomedChange = { [weak self] zoomed in self?.onZoomed?(zoomed) }
        view.insertSubview(scroll, at: 0)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.scroll = scroll
    }
}

@MainActor private func clearRootView() -> UIView {
    let root = UIView()
    root.backgroundColor = .clear
    return root
}
