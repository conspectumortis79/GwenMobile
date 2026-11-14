import GwenMobileKit
import UIKit
#if canImport(VisionKit) && !targetEnvironment(macCatalyst)
import VisionKit
#endif

@MainActor
final class DocumentScannerSystem: NSObject, DocumentScanning, UIAdaptivePresentationControllerDelegate {
    static let shared = DocumentScannerSystem()
    private var continuation: CheckedContinuation<[UIImage]?, Never>?
    private var controller: UIViewController?

    #if DEBUG
    nonisolated(unsafe) static var isSupportedOverride: Bool?
    #endif

    var isSupported: Bool {
        #if DEBUG
        if let supported = Self.isSupportedOverride { return supported }
        #endif
        #if canImport(VisionKit) && !targetEnvironment(macCatalyst)
        return VNDocumentCameraViewController.isSupported
        #else
        return false
        #endif
    }

    func scan() async -> [UIImage]? {
        guard continuation == nil else { return nil }
        #if canImport(VisionKit) && !targetEnvironment(macCatalyst)
        if isSupported {
            let controller = VNDocumentCameraViewController()
            controller.delegate = self
            self.controller = controller
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    guard Presenter.presentIfPossible(controller) else {
                        self.controller = nil
                        self.continuation = nil
                        continuation.resume(returning: nil)
                        return
                    }
                    controller.presentationController?.delegate = self
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancelScan() }
            }
        }
        #endif
        return await CameraPresenter.shared.capture().map { [$0] }
    }

    private func resume(_ pages: [UIImage]?) {
        controller?.presentationController?.delegate = nil
        controller = nil
        continuation?.resume(returning: pages)
        continuation = nil
    }

    private func cancelScan() {
        guard continuation != nil else { return }
        let controller = self.controller
        self.controller = nil
        controller?.dismiss(animated: true)
        resume(nil)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        resume(nil)
    }
}

#if canImport(VisionKit) && !targetEnvironment(macCatalyst)
extension DocumentScannerSystem: @preconcurrency VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true)
        flowMark("SCAN kamera seiten=\(pages.count)")
        resume(pages)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        resume(nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFailWithError error: Error) {
        controller.dismiss(animated: true)
        flowMark("SCAN kamera fehler=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
        resume(nil)
    }
}
#endif

enum DocumentScannerSystemInstall {
    @MainActor static func install() {
        DocumentScannerPort.current = DocumentScannerSystem.shared
    }
}
