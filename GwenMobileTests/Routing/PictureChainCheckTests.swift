@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PictureChainCheckTests: GwenTestCase {
    func testACreateFollowedByAnEditIsOnePictureGroup() {
        let decisions = [ToolDecision(route: .imageCreate, picturePrompt: "frau"),
                         ToolDecision(route: .imageEdit, pictureInstruction: "mann daneben")]
        XCTAssertEqual(PictureChainCheck.groups(in: decisions), [[0, 1]])
    }

    func testTwoCreatesFormOnePictureGroup() {
        let decisions = [ToolDecision(route: .imageCreate, picturePrompt: "frau"),
                         ToolDecision(route: .imageCreate, picturePrompt: "mann daneben")]
        XCTAssertEqual(PictureChainCheck.groups(in: decisions), [[0, 1]])
    }

    func testTwoEditsFormOnePictureGroup() {
        let decisions = [ToolDecision(route: .imageEdit, pictureInstruction: "heller"),
                         ToolDecision(route: .imageEdit, pictureInstruction: "gelber")]
        XCTAssertEqual(PictureChainCheck.groups(in: decisions), [[0, 1]])
    }

    func testTheRouterMergesSeveralChangesIntoOneEdit() async {
        let first = ToolDecision(route: .imageEdit, pictureInstruction: "die nase doppelt so gross",
                                 wish: "die nase doppelt so gross")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "die haare zerzaust",
                                  wish: "die haare zerzaust")
        let fresh = ToolDecision(route: .imageEdit,
                                 pictureInstruction: "die nase doppelt so gross und die haare zerzaust")
        let asked = LockedValue<[(String, String)]>([])
        let checked = await PictureChainCheck.reconciled(
            [first, second], message: "die nase doppelt so gross und die haare zerzaust") { text, hint in
                asked.mutate { $0.append((text, hint)) }
                return [fresh]
            }
        XCTAssertEqual(checked.map(\.stepKind), [.edit])
        XCTAssertEqual(checked.first?.pictureInstruction,
                       "die nase doppelt so gross und die haare zerzaust")
        XCTAssertEqual(checked.first?.wish, "die nase doppelt so gross\ndie haare zerzaust")
        XCTAssertEqual(asked.current.count, 1)
        XCTAssertFalse(asked.current.first?.1.isEmpty ?? true)
    }

    func testTheRouterKeepsSeparateEditsForSeparateResults() async {
        let first = ToolDecision(route: .imageEdit, pictureInstruction: "variante mit grosser nase",
                                 wish: "eine variante mit grosser nase")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "variante mit sauberen haaren",
                                  wish: "eine variante mit sauberen haaren")
        let checked = await PictureChainCheck.reconciled([first, second], message: "vier varianten") { _, _ in
            [ToolDecision(route: .imageEdit, pictureInstruction: "variante mit grosser nase"),
             ToolDecision(route: .imageEdit, pictureInstruction: "variante mit sauberen haaren")]
        }
        XCTAssertEqual(checked, [first, second])
    }

    func testAnEditChainIsNeverCollapsedIntoACreate() async {
        let first = ToolDecision(route: .imageEdit, pictureInstruction: "heller", wish: "heller")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "gelber", wish: "gelber")
        let checked = await PictureChainCheck.reconciled([first, second], message: "heller und gelber") { _, _ in
            [ToolDecision(route: .imageCreate, picturePrompt: "ein bild")]
        }
        XCTAssertEqual(checked, [first, second])
    }

    func testASinglePictureStepNeedsNoCheck() {
        XCTAssertTrue(PictureChainCheck.groups(in: [ToolDecision(route: .imageCreate,
                                                                 picturePrompt: "frau")]).isEmpty)
        XCTAssertTrue(PictureChainCheck.groups(in: [ToolDecision(route: .imageEdit,
                                                                 pictureInstruction: "heller")]).isEmpty)
    }

    func testAPictureStepSeparatedByAnotherTaskIsNoGroup() {
        let decisions = [ToolDecision(route: .imageCreate, picturePrompt: "frau"),
                         ToolDecision(route: .chat),
                         ToolDecision(route: .imageEdit, pictureInstruction: "heller")]
        XCTAssertTrue(PictureChainCheck.groups(in: decisions).isEmpty)
    }

    func testAGalleryStepIsNoPictureCreationGroup() {
        let decisions = [ToolDecision(route: .pictureSearch(query: "frau")),
                         ToolDecision(route: .imageEdit, pictureInstruction: "heller")]
        XCTAssertTrue(PictureChainCheck.groups(in: decisions).isEmpty)
    }

    func testALocalMonochromeStepStaysASeparateDecision() {
        let decisions = [ToolDecision(route: .imageCreate, picturePrompt: "frau"),
                         ToolDecision(route: .imageEdit, pictureMonochrome: true)]
        XCTAssertTrue(PictureChainCheck.groups(in: decisions).isEmpty)
    }

    func testTheRouterCanCollapseASplitPictureIntoOneCreate() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "frau", wish: "eine frau")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "mann daneben",
                                  wish: "daneben ein mann")
        let fresh = ToolDecision(route: .imageCreate, picturePrompt: "eine frau und daneben ein mann")
        let asked = LockedValue<[(String, String)]>([])
        let checked = await PictureChainCheck.reconciled([first, second],
                                                         message: "eine frau und daneben ein mann") { text, hint in
            asked.mutate { $0.append((text, hint)) }
            return [fresh]
        }
        XCTAssertEqual(checked.map(\.stepKind), [.create])
        XCTAssertEqual(checked.first?.picturePrompt, "eine frau und daneben ein mann")
        XCTAssertEqual(checked.first?.wish, "eine frau\ndaneben ein mann")
        XCTAssertEqual(asked.current.count, 1)
        XCTAssertEqual(asked.current.first?.0, "eine frau und daneben ein mann")
        XCTAssertFalse(asked.current.first?.1.isEmpty ?? true)
    }

    func testTheRouterKeepsSeparatePictureStepsWhenItConfirmsThem() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "ball", wish: "male einen ball")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiss",
                                  wish: "mach das neue bild schwarz-weiss")
        let fresh = [ToolDecision(route: .imageCreate, picturePrompt: "ball"),
                     ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiss")]
        let checked = await PictureChainCheck.reconciled([first, second], message: "ball und schwarz-weiss") { _, _ in
            fresh
        }
        XCTAssertEqual(checked.map(\.stepKind), [.create, .edit])
        XCTAssertEqual(checked, [first, second])
    }

    func testAnUnhelpfulRouterAnswerLeavesThePlanAlone() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "ball", wish: "male einen ball")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiss",
                                  wish: "mach das neue bild schwarz-weiss")
        let empty = await PictureChainCheck.reconciled([first, second], message: "ball und schwarz-weiss") { _, _ in
            nil
        }
        XCTAssertEqual(empty, [first, second])
        let onlyEdit = await PictureChainCheck.reconciled([first, second], message: "ball und schwarz-weiss") { _, _ in
            [ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiss")]
        }
        XCTAssertEqual(onlyEdit, [first, second])
        let onlyChat = await PictureChainCheck.reconciled([first, second], message: "ball und schwarz-weiss") { _, _ in
            [ToolDecision(route: .chat)]
        }
        XCTAssertEqual(onlyChat, [first, second])
    }

    func testASingleCreateReplacesTheGroupAndKeepsTheFollowingTasks() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "frau", wish: "eine frau")
        let second = ToolDecision(route: .imageEdit, pictureInstruction: "mann daneben",
                                  wish: "daneben ein mann")
        let after = ToolDecision(route: .calendar)
        let fresh = ToolDecision(route: .imageCreate, picturePrompt: "eine frau und ein mann")
        let checked = await PictureChainCheck.reconciled([first, second, after], message: "frau und mann") { _, _ in
            [fresh]
        }
        XCTAssertEqual(checked.map(\.stepKind), [.create, .calendar])
        XCTAssertEqual(checked.last, after)
    }
}
