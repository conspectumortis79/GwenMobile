import SwiftUI

struct ImageViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ImageViewerModel
    @State private var index: Int

    private let target: ImagePreviewTarget

    init(target: ImagePreviewTarget, reader: ViewerImageReading) {
        self.target = target
        self.index = target.startIndex
        _model = StateObject(wrappedValue: ImageViewerModel(files: target.files, reader: reader))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            page
            chrome
        }
        .statusBarHidden(true)
        .onAppear { model.load(index) }
        .onChange(of: index) { _, next in model.load(next) }
    }

    @ViewBuilder private var page: some View {
        switch model.page(index) {
        case .loading:
            ProgressView()
                .tint(.white)
        case .ready(let image):
            ZoomableImageView(image: image)
                .id(target.files[index])
        case .unavailable:
            Text(L.t("image_gone"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
                }
                .accessibilityLabel(L.t("close_image"))
            }
            Spacer()
            if target.files.count > 1 { pager }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var pager: some View {
        HStack(spacing: 26) {
            Button { index -= 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold))
            }
            .accessibilityLabel(L.t("previous_picture"))
            .disabled(index == target.files.startIndex)
            Text(verbatim: "\(index + 1) / \(target.files.count)")
                .font(.system(size: 14, weight: .semibold))
            Button { index += 1 } label: {
                Image(systemName: "chevron.right").font(.system(size: 22, weight: .semibold))
            }
            .accessibilityLabel(L.t("next_picture"))
            .disabled(index == target.files.count - 1)
        }
        .foregroundStyle(.white)
    }
}
