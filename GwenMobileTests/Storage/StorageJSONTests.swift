import XCTest
import GwenMobileKit

final class StorageJSONTests: GwenTestCase {
    private func recordedNotes() -> (FailureReporter, LockedValue<[String]>) {
        let failures = FailureReporter(label: "ABLAGE-test")
        let notes = LockedValue<[String]>([])
        failures.report { message in notes.mutate { $0.append(message) } }
        return (failures, notes)
    }

    private func file(_ name: String) throws -> URL {
        let paths = temporaryPaths("storagejson")
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        return paths.support.appendingPathComponent(name)
    }

    func testAMissingFileReturnsNothingWithoutAFailure() {
        let (failures, notes) = recordedNotes()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("storagejson-missing-\(UUID().uuidString).json")
        XCTAssertNil(StorageJSON.read([Int].self, from: url, failures: failures))
        XCTAssertTrue(notes.current.isEmpty)
    }

    func testReadableContentComesBack() throws {
        let (failures, notes) = recordedNotes()
        let url = try file("values.json")
        try Data("[1,2,3]".utf8).write(to: url)
        XCTAssertEqual(StorageJSON.read([Int].self, from: url, failures: failures), [1, 2, 3])
        XCTAssertTrue(notes.current.isEmpty)
    }

    func testUnreadableContentIsReportedInsteadOfThrown() throws {
        let (failures, notes) = recordedNotes()
        let url = try file("broken.json")
        try Data("kein json".utf8).write(to: url)
        XCTAssertNil(StorageJSON.read([Int].self, from: url, failures: failures))
        XCTAssertEqual(notes.current.count, 1)
        XCTAssertTrue(notes.current[0].contains("lesen fehlgeschlagen"), notes.current[0])
        let folder = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0 == url.lastPathComponent + ".corrupt" }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(backups.first))),
                       Data("kein json".utf8))
    }

    func testWritingKeepsReadableContent() throws {
        let (failures, notes) = recordedNotes()
        let url = try file("written.json")
        XCTAssertTrue(StorageJSON.write([1, 2, 3], to: url, support: url.deletingLastPathComponent(),
                                        failures: failures))
        XCTAssertTrue(notes.current.isEmpty)
        XCTAssertEqual(StorageJSON.read([Int].self, from: url, failures: failures), [1, 2, 3])
    }

    func testAFailedProtectionStillKeepsTheWrittenContent() throws {
        let original = StorageJSON.protect
        defer { StorageJSON.protect = original }
        StorageJSON.protect = { _ in throw APIError(message: "kaputt") }
        let (failures, notes) = recordedNotes()
        let url = try file("protected.json")
        XCTAssertTrue(StorageJSON.write([1, 2, 3], to: url, support: url.deletingLastPathComponent(),
                                        failures: failures))
        XCTAssertTrue(notes.current.isEmpty)
        XCTAssertEqual(StorageJSON.read([Int].self, from: url, failures: failures), [1, 2, 3])
    }
}
