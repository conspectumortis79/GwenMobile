@testable import GwenMobileFeatureCore
import Foundation

@MainActor
protocol CodeFilePresenting {
    func present(url: URL) throws
}

@MainActor
struct SystemCodeFilePresenter: CodeFilePresenting {
    func present(url: URL) throws {
        try Presenter.share(url: url)
    }
}
