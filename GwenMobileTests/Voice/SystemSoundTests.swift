@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private final class TallyCue: SoundCueing {
    private(set) var plays = 0

    func play() { plays += 1 }
}

@MainActor
private final class FakeFiles: SoundFilePlaying {
    private(set) var paths: [String] = []
    var works = true

    func play(path: String) -> Bool {
        paths.append(path)
        return works
    }
}

final class SystemSoundCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gwen-sounds-\(UUID().uuidString)")
        for relative in ["Tink.caf", "begin_record.caf", "New/Bloom.caf", "nano/Alarm_Haptic.caf",
                         "liesmich.txt", ".versteckt.caf", "Sounds/Glass.aiff"] {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEverySoundFileIsListedWithItsFolderAndNothingElse() {
        let sounds = SystemSoundCatalog(root: root).sounds()
        XCTAssertEqual(sounds.map(\.name), ["begin record", "Tink", "Bloom", "Glass", "Alarm Haptic"])
        XCTAssertEqual(sounds.map(\.folder), ["", "", "New", "Sounds", "nano"])
        XCTAssertTrue(sounds.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testTheFirstReadableRootWins() throws {
        let missing = root.appendingPathComponent("gibt-es-nicht").path
        let found = try XCTUnwrap(SystemSoundCatalog.live(roots: [missing, root.path]))
        XCTAssertEqual(found.root.path, root.path)
        XCTAssertNil(SystemSoundCatalog.live(roots: [missing]))
    }

    func testTheLiveRootsNameTheIPhoneAndTheMacFolders() {
        XCTAssertEqual(SystemSoundCatalog.liveRoots, ["/System/Library/Audio/UISounds", "/System/Library/Sounds"])
    }

    func testANameIsReadOffAStoredPath() {
        XCTAssertEqual(SystemSoundCatalog.name(ofPath: "/System/Library/Audio/UISounds/jbl_confirm.caf"),
                       "jbl confirm")
    }
}

final class SystemSoundGroupTests: GwenTestCase {
    private let sounds = [SystemSound(path: "/a/Tink.caf", name: "Tink", folder: ""),
                          SystemSound(path: "/a/Tock.caf", name: "Tock", folder: ""),
                          SystemSound(path: "/a/New/Bloom.caf", name: "Bloom", folder: "New")]

    func testGroupsKeepTheCatalogOrder() {
        let groups = SystemSoundGroup.grouped(sounds, matching: "")
        XCTAssertEqual(groups.map(\.folder), ["", "New"])
        XCTAssertEqual(groups.first?.sounds.map(\.name), ["Tink", "Tock"])
    }

    func testTheSearchIgnoresCaseAndDropsEmptyFolders() {
        let groups = SystemSoundGroup.grouped(sounds, matching: " bLOOM ")
        XCTAssertEqual(groups.map(\.folder), ["New"])
        XCTAssertTrue(SystemSoundGroup.grouped(sounds, matching: "gibt es nicht").isEmpty)
    }

    func testTheLabelsNameTheDefaultAndTheMainFolder() {
        XCTAssertEqual(CueSoundLabel.name(of: ""), "GwenMobile tone (default)")
        XCTAssertEqual(CueSoundLabel.name(of: "/a/New/Bloom.caf"), "Bloom")
        XCTAssertEqual(CueSoundLabel.folder(""), "System")
        XCTAssertEqual(CueSoundLabel.folder("New"), "New")
    }
}

@MainActor
final class ChosenCueTests: XCTestCase {
    func testWithoutAChoiceTheGwenMobileToneSounds() {
        let chime = TallyCue()
        let files = FakeFiles()
        ChosenCue(chosen: { "  " }, chime: chime, files: files).play()
        XCTAssertEqual(chime.plays, 1)
        XCTAssertTrue(files.paths.isEmpty)
    }

    func testAChosenSystemSoundReplacesTheTone() {
        let chime = TallyCue()
        let files = FakeFiles()
        ChosenCue(chosen: { "/System/Library/Audio/UISounds/Tink.caf" }, chime: chime, files: files).play()
        XCTAssertEqual(files.paths, ["/System/Library/Audio/UISounds/Tink.caf"])
        XCTAssertEqual(chime.plays, 0, "nie zwei Töne übereinander")
    }

    func testAnUnplayableFileFallsBackToTheTone() {
        let chime = TallyCue()
        let files = FakeFiles()
        files.works = false
        ChosenCue(chosen: { "/weg/Tink.caf" }, chime: chime, files: files).play()
        XCTAssertEqual(chime.plays, 1, "ein fehlender Ton darf das Signal nie verschlucken")
    }

    func testTheChoiceIsReadAtEveryPlay() {
        let chosen = LockedValue("")
        let chime = TallyCue()
        let files = FakeFiles()
        let cue = ChosenCue(chosen: { chosen.current }, chime: chime, files: files)
        cue.play()
        chosen.set("/a/Bloom.caf")
        cue.play()
        XCTAssertEqual(chime.plays, 1)
        XCTAssertEqual(files.paths, ["/a/Bloom.caf"], "eine neue Wahl gilt ohne Neustart")
    }

    func testTheRealPlayerRefusesAMissingFile() {
        XCTAssertFalse(SoundFilePlayer().play(path: "/gibt/es/nicht.caf"))
    }
}
