@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
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
            ImagePagerView(pages: pages, index: $index)
            chrome
        }
        .statusBarHidden(true)
        .windowAppearance()
        .onAppear {
            model.load(index)
            model.preload(around: index)
        }
        .onChange(of: index) { _, next in
            model.load(next)
            model.preload(around: next)
        }
    }

    private var pages: [ViewerPage] {
        target.files.indices.map { position in
            switch model.page(position) {
            case .loading: ViewerPage.loading
            case .ready(let image): ViewerPage.ready(image)
            case .unavailable: ViewerPage.unavailable
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: TapProbe.action({ dismiss() })) {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(30)
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
            Button(action: TapProbe.action({ turn(.back) })) {
                Image(systemName: "chevron.left").scaledFont(22, weight: .semibold)
            }
            .accessibilityLabel(L.t("previous_picture"))
            .disabled(ViewerStep.back.target(from: index, count: target.files.count) == nil)
            Text(verbatim: "\(index + 1) / \(target.files.count)")
                .scaledFont(14, weight: .semibold)
            Button(action: TapProbe.action({ turn(.forward) })) {
                Image(systemName: "chevron.right").scaledFont(22, weight: .semibold)
            }
            .accessibilityLabel(L.t("next_picture"))
            .disabled(ViewerStep.forward.target(from: index, count: target.files.count) == nil)
        }
        .foregroundStyle(.white)
    }

    private func turn(_ step: ViewerStep) {
        guard let next = step.target(from: index, count: target.files.count) else { return }
        index = next
    }
}
