@testable import GwenMobileDevice
import Foundation
import UIKit
import XCTest
import GwenMobileKit

private let scrollFile = "UIScrollEvent.m"
private let scrollLine = 618
private let scrollMessage = "Missing expected nonaccelerated scroll delta"
private let adjustSelector = NSSelectorFromString("_adjustedDeltaForPanWithAcceleration:honoringScrollDirectionPreference:")

private final class ScrollEventProbe: NSObject {}

private final class FailureRecorder {
    private(set) var entries: [AssertionFailure] = []

    func record(_ failure: AssertionFailure) {
        entries.append(failure)
    }
}

private struct NeverTolerating: AssertionTolerance {
    func tolerates(_ failure: AssertionFailure) -> Bool { false }
}

private func scrollFailure(file: String = scrollFile, message: String = scrollMessage) -> AssertionFailure {
    AssertionFailure.method(adjustSelector, object: ScrollEventProbe(), file: file, lineNumber: scrollLine, description: message)
}

@MainActor
final class ScrollAssertionShieldTests: GwenTestCase {
    private func shielded() -> (TolerantAssertionHandler, FailureRecorder, FailureRecorder) {
        let suppressed = FailureRecorder()
        let escalated = FailureRecorder()
        let subject = TolerantAssertionHandler(tolerance: MissingNonAcceleratedScrollDeltaTolerance(),
                                               onSuppression: suppressed.record,
                                               onEscalation: escalated.record)
        return (subject, suppressed, escalated)
    }

    func testMissingScrollDeltaFailureIsTolerated() {
        XCTAssertTrue(MissingNonAcceleratedScrollDeltaTolerance().tolerates(scrollFailure()))
    }

    func testToleranceAcceptsTheFailureWithAFullPath() {
        let nested = scrollFailure(file: "/Build/Products/UIKitCore/UIScrollEvent.m")
        XCTAssertTrue(MissingNonAcceleratedScrollDeltaTolerance().tolerates(nested))
    }

    func testFailureFromAnotherFileIsNotTolerated() {
        XCTAssertFalse(MissingNonAcceleratedScrollDeltaTolerance().tolerates(scrollFailure(file: "UIWindow.m")))
    }

    func testFailureWithAnotherMessageIsNotTolerated() {
        XCTAssertFalse(MissingNonAcceleratedScrollDeltaTolerance().tolerates(scrollFailure(message: "Invalid parameter not satisfying: delta")))
    }

    func testCombinedToleranceToleratesWhatAnyPartTolerates() {
        let combined = CombinedTolerance(parts: [NeverTolerating(), MissingNonAcceleratedScrollDeltaTolerance()])
        XCTAssertTrue(combined.tolerates(scrollFailure()))
        XCTAssertFalse(combined.tolerates(scrollFailure(message: "Nothing known about this one")))
    }

    func testToleratedMethodFailureIsSuppressedAndNeverEscalated() {
        let (subject, suppressed, escalated) = shielded()
        subject.handleMethodFailure(adjustSelector, object: ScrollEventProbe(), file: scrollFile,
                                    lineNumber: scrollLine, description: scrollMessage)
        XCTAssertEqual(suppressed.entries.count, 1)
        XCTAssertTrue(escalated.entries.isEmpty)
    }

    func testOtherMethodFailureKeepsEscalating() {
        let (subject, suppressed, escalated) = shielded()
        subject.handleMethodFailure(adjustSelector, object: ScrollEventProbe(), file: "UIScrollView.m",
                                    lineNumber: 12, description: "offset is NaN")
        XCTAssertTrue(suppressed.entries.isEmpty)
        XCTAssertEqual(escalated.entries.count, 1)
        XCTAssertEqual(escalated.entries.first?.file, "UIScrollView.m")
        XCTAssertEqual(escalated.entries.first?.line, 12)
        XCTAssertEqual(escalated.entries.first?.message, "offset is NaN")
    }

    func testToleratedFunctionFailureIsSuppressedAndNeverEscalated() {
        let (subject, suppressed, escalated) = shielded()
        subject.handleFunctionFailure(function: "_UIScrollEventComputeDelta", file: scrollFile,
                                      lineNumber: scrollLine, description: scrollMessage)
        XCTAssertEqual(suppressed.entries.count, 1)
        XCTAssertEqual(suppressed.entries.first?.site, "_UIScrollEventComputeDelta")
        XCTAssertTrue(escalated.entries.isEmpty)
    }

    func testOtherFunctionFailureKeepsEscalating() {
        let (subject, suppressed, escalated) = shielded()
        subject.handleFunctionFailure(function: "_UIScrollEventComputeDelta", file: "UIScrollView.m",
                                      lineNumber: 12, description: "offset is NaN")
        XCTAssertTrue(suppressed.entries.isEmpty)
        XCTAssertEqual(escalated.entries.count, 1)
    }

    func testShieldAnswersTheObjectiveCFailureSelectors() {
        let (subject, _, _) = shielded()
        XCTAssertTrue(subject.responds(to: NSSelectorFromString("handleFailureInMethod:object:file:lineNumber:description:")))
        XCTAssertTrue(subject.responds(to: NSSelectorFromString("handleFailureInFunction:file:lineNumber:description:")))
    }

    func testSiteNamesTheFailingClassAndSelector() {
        let failure = scrollFailure()
        XCTAssertTrue(failure.site.contains("ScrollEventProbe"))
        XCTAssertTrue(failure.site.contains("_adjustedDeltaForPanWithAcceleration:honoringScrollDirectionPreference:"))
    }

    func testEscalatedFailureCarriesTheSystemExceptionName() {
        let thrown = NSException(assertion: scrollFailure())
        XCTAssertEqual(thrown.name, .internalInconsistencyException)
        XCTAssertTrue(thrown.reason?.contains("\(scrollFile):\(scrollLine)") == true)
        XCTAssertTrue(thrown.reason?.contains(scrollMessage) == true)
    }

    func testInstallMakesTheShieldTheCurrentHandlerOfThisThread() {
        let dictionary = Thread.current.threadDictionary
        let key = NSAssertionHandlerKey as NSString
        let previous = dictionary.object(forKey: key)
        addTeardownBlock {
            if let previous {
                dictionary.setObject(previous, forKey: key)
            } else {
                dictionary.removeObject(forKey: key)
            }
        }
        ScrollAssertionShield.install()
        XCTAssertTrue(NSAssertionHandler.current is TolerantAssertionHandler)
        XCTAssertTrue(dictionary.object(forKey: key) is TolerantAssertionHandler)
    }

    func testSmokeProductionWiringKeepsWorkingForTheScrollFailure() {
        ScrollAssertionShield.handler().handleMethodFailure(adjustSelector, object: ScrollEventProbe(),
                                                           file: scrollFile, lineNumber: scrollLine,
                                                           description: scrollMessage)
    }
}
