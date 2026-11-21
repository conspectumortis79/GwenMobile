@testable import GwenMobileFeatureCore
import MediaPlayer
import XCTest

#if !targetEnvironment(macCatalyst)
@MainActor
final class MediaLibraryDefaultsTests: GwenTestCase {
    func testTheDefaultReaderIsEmptyAndDenied() async {
        XCTAssertEqual(MediaLibraryReader.authorizationStatus(), .denied)
        let requested = await MediaLibraryReader.requestAuthorization()
        XCTAssertEqual(requested, .denied)
        let access = await MediaLibraryReader().access()
        XCTAssertFalse(access)
        XCTAssertTrue(MediaLibraryIndex.playlists().isEmpty)
        XCTAssertTrue(MediaLibraryIndex.artists().isEmpty)
        XCTAssertTrue(MediaLibraryIndex.albums().isEmpty)
        XCTAssertTrue(MediaLibraryIndex.songs().isEmpty)
        XCTAssertTrue(MediaLibraryIndex.entries(of: .playlist).isEmpty)
        XCTAssertTrue(MediaLibraryIndex.entries(of: .artist).isEmpty)
        XCTAssertTrue(MediaLibraryIndex.entries(of: .album).isEmpty)
        XCTAssertTrue(MediaLibraryIndex.entries(of: .song).isEmpty)
        let entries = await MediaLibraryReader().entries(of: [.playlist, .artist, .album, .song])
        XCTAssertTrue(entries.isEmpty)
    }
}
#endif
