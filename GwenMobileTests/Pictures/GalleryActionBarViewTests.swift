@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class GalleryActionBarViewTests: GwenTestCase {
    private func plan(selected: Int, total: Int, progress: GalleryProgress? = nil,
                      result: GalleryResult? = nil) -> GalleryBarPlan {
        GalleryBarPlan.make(selected: selected, total: total, progress: progress, result: result)
    }

    func testEveryPlanDraws() async throws {
        let plans = [
            plan(selected: 0, total: 0),
            plan(selected: 2, total: 5),
            plan(selected: 3, total: 3, progress: GalleryProgress(total: 3, done: 1)),
            plan(selected: 0, total: 3, result: .saved(3)),
            plan(selected: 0, total: 3, result: .denied),
            plan(selected: 0, total: 3, result: .failed)
        ]
        for item in plans {
            let controller = mountView(GalleryActionBar(plan: item, onSave: {}, onShare: {},
                                                        onSaveAll: {}, onCancel: {}),
                                       size: CGSize(width: 390, height: 200))
            try await settleHosted(controller, milliseconds: 120)
            XCTAssertNotNil(controller.view.window)
        }
    }

    func testTheBarWithSelectionAndResultDraws() {
        XCTAssertNotNil(renderView(GalleryActionBar(plan: plan(selected: 2, total: 5), onSave: {},
                                                    onShare: {}, onSaveAll: {}, onCancel: {}), width: 390))
        XCTAssertNotNil(renderView(GalleryActionBar(plan: plan(selected: 0, total: 3, result: .saved(2)),
                                                    onSave: {}, onShare: {}, onSaveAll: {}, onCancel: {}),
                                   width: 390))
    }
}
