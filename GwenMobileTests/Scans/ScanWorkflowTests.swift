@testable import GwenMobileFeatureCore
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ScanWorkflowTests: GwenTestCase {
    private func page(_ size: CGSize = CGSize(width: 200, height: 300)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            UIBezierPath(rect: CGRect(x: 10, y: 10, width: 80, height: 20)).stroke()
        }
    }

    func testTheWorkflowStoresPagesAsAPDF() throws {
        let paths = temporaryPaths("scan-workflow")
        let documents = DocumentStore(paths: paths)
        documents.prepareDirectories()
        var workflow = ScanWorkflow()
        workflow.recognize = { _, _ in "Zeile eins\nZeile zwei" }
        let outcome = try XCTUnwrap(workflow.store(pages: [page(), page()], kind: .receipt,
                                                   date: Date(), documents: documents))
        XCTAssertEqual(outcome.attachment.kind, .pdf)
        XCTAssertEqual(outcome.attachment.pages, 2)
        XCTAssertEqual(outcome.attachment.via, .ocr)
        XCTAssertFalse(outcome.text.isEmpty)
        XCTAssertNotNil(documents.text(named: outcome.attachment.file))
        XCTAssertNil(workflow.store(pages: [], kind: .receipt, date: Date(), documents: documents))
    }

    func testAWorkflowWithoutReadableTextStillStoresThePDF() throws {
        let paths = temporaryPaths("scan-workflow-silent")
        let documents = DocumentStore(paths: paths)
        documents.prepareDirectories()
        var workflow = ScanWorkflow()
        workflow.recognize = { _, _ in "" }
        let outcome = try XCTUnwrap(workflow.store(pages: [page()], kind: .letter,
                                                   date: Date(), documents: documents))
        XCTAssertEqual(outcome.attachment.via, .none)
        XCTAssertTrue(outcome.text.isEmpty)
    }

    func testThePageFittingKeepsTheAspectRatio() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(ScanWorkflow.fitted(CGSize(width: 100, height: 100), in: box),
                       CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertEqual(ScanWorkflow.fitted(.zero, in: box), box)
    }
}
