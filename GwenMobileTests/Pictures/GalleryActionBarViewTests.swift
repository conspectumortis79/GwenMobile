@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class GalleryActionBarViewTests: GwenTestCase {
    func testEveryPlanDraws() async throws {
        let plans = [
            Fixtures.galleryPlan(selected: 0, total: 0),
            Fixtures.galleryPlan(selected: 2, total: 5),
            Fixtures.galleryPlan(selected: 3, total: 3, progress: GalleryProgress(total: 3, done: 1)),
            Fixtures.galleryPlan(selected: 0, total: 3, result: .saved(3)),
            Fixtures.galleryPlan(selected: 0, total: 3, result: .denied),
            Fixtures.galleryPlan(selected: 0, total: 3, result: .failed)
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
        XCTAssertNotNil(renderView(GalleryActionBar(plan: Fixtures.galleryPlan(selected: 2, total: 5), onSave: {},
                                                    onShare: {}, onSaveAll: {}, onCancel: {}), width: 390))
        XCTAssertNotNil(renderView(GalleryActionBar(plan: Fixtures.galleryPlan(selected: 0, total: 3, result: .saved(2)),
                                                    onSave: {}, onShare: {}, onSaveAll: {}, onCancel: {}),
                                   width: 390))
    }
}
