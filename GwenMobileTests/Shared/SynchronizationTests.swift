import XCTest
import GwenMobileKit

final class SynchronizationTests: XCTestCase {
    func testLockedValueKeepsAndReplacesItsContent() {
        let value = LockedValue(3)
        XCTAssertEqual(value.current, 3)
        XCTAssertEqual(value.exchange(5), 3)
        XCTAssertEqual(value.current, 5)
        value.set(9)
        XCTAssertEqual(value.current, 9)
    }

    func testMutateRunsTheChangeAtomicallyAndReportsTheResult() {
        let counter = LockedValue(0)
        let raised = counter.mutate { stored in
            stored += 4
            return stored
        }
        XCTAssertEqual(raised, 4)
        XCTAssertEqual(counter.current, 4)
    }

    func testLockedValueSurvivesConcurrentBumps() {
        let counter = LockedValue(0)
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            counter.mutate { stored in stored += 1 }
        }
        XCTAssertEqual(counter.current, 200)
    }

    func testLockedDictionaryReadsWritesAndRemoves() {
        let store = LockedDictionary<String, Int>()
        XCTAssertNil(store.value(for: "a"))
        store.setValue(1, for: "a")
        store.setValue(2, for: "b")
        XCTAssertEqual(store.value(for: "a"), 1)
        XCTAssertEqual(store.value(for: "b"), 2)
        store.removeValue(for: "a")
        XCTAssertNil(store.value(for: "a"))
        XCTAssertEqual(store.value(for: "b"), 2)
    }

    func testRewritingAKeyKeepsTheEntryCount() {
        let store = LockedDictionary<String, Int>(capacity: 2)
        store.setValue(1, for: "a")
        store.setValue(7, for: "a")
        store.setValue(2, for: "b")
        XCTAssertEqual(store.value(for: "a"), 7, "ein überschriebener Schlüssel belegt nur einen Platz")
        XCTAssertEqual(store.value(for: "b"), 2)
    }

    func testCapacityDropsTheOldestKeyFirst() {
        let store = LockedDictionary<String, Int>(capacity: 2)
        store.setValue(1, for: "a")
        store.setValue(2, for: "b")
        store.setValue(3, for: "c")
        XCTAssertNil(store.value(for: "a"))
        XCTAssertEqual(store.value(for: "b"), 2)
        XCTAssertEqual(store.value(for: "c"), 3)
    }

    func testRewritingAValueKeepsThePlaceInLineForEviction() {
        let store = LockedDictionary<String, Int>(capacity: 2)
        store.setValue(1, for: "a")
        store.setValue(2, for: "b")
        store.setValue(3, for: "a")
        store.setValue(4, for: "c")
        XCTAssertNil(store.value(for: "a"))
        XCTAssertEqual(store.value(for: "b"), 2)
        XCTAssertEqual(store.value(for: "c"), 4)
    }
}
