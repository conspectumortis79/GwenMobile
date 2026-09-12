import UIKit

@MainActor
final class CameraPresenter: NSObject, ObservableObject,
                             UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {
    static let shared = CameraPresenter()
    var onImage: ((UIImage) -> Void)?

    func present() {
        guard let top = Presenter.topViewController else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let al = UIAlertController(title: L.t("no_camera_title"),
                                       message: L.t("no_camera_msg"),
                                       preferredStyle: .alert)
            al.addAction(UIAlertAction(title: L.t("ok"), style: .default))
            top.present(al, animated: true)
            return
        }
        let pc = UIImagePickerController()
        pc.sourceType = .camera
        pc.delegate = self
        top.present(pc, animated: true)
    }

    func dismissPresented() {
        Presenter.topViewController?.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let t0 = ContinuousClock.now
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage {
                let src = img
                flowMark("CAMERA shot px=\(Int(src.size.width * src.scale))x\(Int(src.size.height * src.scale))")
                Task { @MainActor [weak self] in
                    let small = await Task.detached(priority: .userInitiated) {
                        src.preparingThumbnail(of: CGSize(width: ImagePolicy.uploadMaxPixel,
                                                          height: ImagePolicy.uploadMaxPixel)) ?? src
                    }.value
                    flowMark("CAMERA thumbnail ms=\(msOf(t0.duration(to: .now)))")
                    self?.onImage?(small)
                }
            }
        }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)
        }
    }
}
