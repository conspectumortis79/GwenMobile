@testable import GwenMobileFeatureCore
import GwenMobileKit
import UIKit

@MainActor
final class CameraPresenter: NSObject, ObservableObject,
                             UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {
    static let shared = CameraPresenter()

    #if DEBUG
    nonisolated(unsafe) static var isCameraAvailable: @MainActor () -> Bool = {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    #endif

    var onImage: ((UIImage) -> Void)?
    var isAvailableOverride: Bool?
    var captureOverride: (() async -> UIImage?)?
    nonisolated(unsafe) static var presentCameraOverride: (@MainActor () -> Bool)?
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    var isAvailable: Bool {
        if let isAvailableOverride { return isAvailableOverride }
        return UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func capture() async -> UIImage? {
        if let captureOverride { return await captureOverride() }
        guard Self.cameraIsAvailable else {
            present()
            return nil
        }
        guard captureContinuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            guard presentCamera() else {
                settle(nil)
                return
            }
        }
    }

    func present() {
        guard Self.cameraIsAvailable else {
            let alert = UIAlertController(title: L.t("no_camera_title"),
                                          message: L.t("no_camera_msg"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L.t("ok"), style: .default))
            Presenter.presentIfPossible(alert)
            return
        }
        _ = presentCamera()
    }

    private func presentCamera() -> Bool {
        if let presentCameraOverride = Self.presentCameraOverride { return presentCameraOverride() }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        return Presenter.presentIfPossible(picker)
    }

    private static var cameraIsAvailable: Bool {
        #if DEBUG
        isCameraAvailable()
        #else
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    #if DEBUG
    func dismissPresented() {
        Presenter.topViewController?.dismiss(animated: true)
    }
    #endif

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let t0 = ContinuousClock.now
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else {
            settle(nil)
            return
        }
        let src = img
        flowMark("CAMERA shot px=\(Int(src.size.width * src.scale))x\(Int(src.size.height * src.scale))")
        Task { @MainActor [weak self] in
            let small = await Offload.orNil {
                src.preparingThumbnail(of: CGSize(width: ImagePolicy.uploadMaxPixel,
                                                  height: ImagePolicy.uploadMaxPixel)) ?? src
            } ?? src
            flowMark("CAMERA thumbnail ms=\(msOf(t0.duration(to: .now)))")
            self?.settle(small)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        settle(nil)
    }

    private func settle(_ image: UIImage?) {
        guard let waiting = captureContinuation else {
            if let image { onImage?(image) }
            return
        }
        captureContinuation = nil
        waiting.resume(returning: image)
    }
}
