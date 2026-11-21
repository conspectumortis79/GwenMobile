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
    #if DEBUG
    var isAvailableOverride: Bool?
    var captureOverride: (() async -> UIImage?)?
    nonisolated(unsafe) static var presentCameraOverride: (@MainActor () -> Bool)?
    #endif
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?
    private var capturing = false
    private var captureToken = 0
    private let sheet = SheetPresenter()

    var isAvailable: Bool {
        #if DEBUG
        if let isAvailableOverride { return isAvailableOverride }
        #endif
        return Self.cameraIsAvailable
    }

    func capture() async -> UIImage? {
        #if DEBUG
        if let captureOverride { return await captureOverride() }
        #endif
        guard Self.cameraIsAvailable else {
            present()
            return nil
        }
        guard captureContinuation == nil, !Task.isCancelled else { return nil }
        capturing = true
        captureToken += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                captureContinuation = continuation
                guard !Task.isCancelled, presentCamera() else {
                    settle(nil)
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelCapture() }
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
        #if DEBUG
        if let presentCameraOverride = Self.presentCameraOverride { return presentCameraOverride() }
        #endif
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        return sheet.show(picker, onDismiss: { [weak self] in self?.dismissed() })
    }

    private func dismissed() {
        guard captureContinuation != nil else { return }
        settle(nil)
    }

    private func cancelCapture() {
        guard captureContinuation != nil || capturing else { return }
        captureToken += 1
        capturing = false
        sheet.dismiss(animated: true)
        settle(nil)
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
        let fromCapture = capturing
        let token = captureToken
        flowMark("CAMERA shot px=\(Int(src.size.width * src.scale))x\(Int(src.size.height * src.scale))")
        Task { @MainActor [weak self] in
            let small = await Offload.orNil {
                src.preparingThumbnail(of: CGSize(width: ImagePolicy.uploadMaxPixel,
                                                  height: ImagePolicy.uploadMaxPixel)) ?? src
            } ?? src
            flowMark("CAMERA thumbnail ms=\(msOf(t0.duration(to: .now)))")
            guard let self, !fromCapture || self.captureToken == token else { return }
            self.settle(small)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        settle(nil)
    }

    private func settle(_ image: UIImage?) {
        capturing = false
        sheet.release()
        guard let waiting = captureContinuation else {
            if let image { onImage?(image) }
            return
        }
        captureContinuation = nil
        waiting.resume(returning: image)
    }
}
