@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

final class RecordingSetupTests: XCTestCase {
    func testEverySetupLetsABluetoothHeadsetBeTheMicrophone() {
        for setup in RecordingSetup.preferred {
            XCTAssertTrue(setup.options.contains(.allowBluetoothHFP), "\(setup.label) hört nicht über AirPods")
            XCTAssertTrue(setup.options.contains(.defaultToSpeaker), "\(setup.label) spricht in die Hörmuschel")
            XCTAssertTrue(setup.options.contains(.mixWithOthers), "\(setup.label) mischt sich nicht mehr ein")
            XCTAssertFalse(setup.options.contains(.duckOthers),
                           "\(setup.label) hält die Musik im Zuhörmodus dauerhaft leise - Apple erlaubt das nur kurz")
        }
    }

    func testTheHandsFreeSetupIsAlwaysTheLastResort() {
        XCTAssertEqual(RecordingSetup.preferred.last, RecordingSetup.handsFree)
        XCTAssertEqual(RecordingSetup.handsFree.mode, .measurement)
    }

#if !targetEnvironment(macCatalyst)
    func testFromIOS26FullBluetoothQualityIsTriedFirstInTheOnlyModeItSupports() throws {
        let first = try XCTUnwrap(RecordingSetup.preferred.first)
        XCTAssertTrue(first.options.contains(.bluetoothHighQualityRecording))
        XCTAssertEqual(first.mode, .default, "volle Qualität gibt es laut SDK nur im Standardmodus")
        XCTAssertEqual(RecordingSetup.preferred.count, 2)
    }
#endif
}

final class MicrophoneRouteTests: XCTestCase {
    func testTheQualityTellsWhetherFullBandwidthIsOnOrOnlyPossible() {
        XCTAssertEqual(BluetoothQuality.of(supported: true, enabled: true), .full)
        XCTAssertEqual(BluetoothQuality.of(supported: true, enabled: false), .possible)
        XCTAssertEqual(BluetoothQuality.of(supported: false, enabled: false), .none)
    }

    func testTheLineNamesMicrophoneAndOutputWithTheirQuality() {
        let airPods = RoutePort(kind: "BluetoothHFP", name: "AirPods Pro", quality: .full)
        let speaker = RoutePort(kind: "Speaker", name: "Lautsprecher", quality: nil)
        XCTAssertEqual(MicrophoneRoute.line(inputs: [airPods], outputs: [speaker]),
                       "eingang=BluetoothHFP[AirPods Pro] qualitaet=voll ausgang=Speaker[Lautsprecher]")
        XCTAssertEqual(MicrophoneRoute.line(inputs: [], outputs: []), "eingang=- ausgang=-")
    }

    func testRouteChangeReasonsAreNamed() {
        XCTAssertEqual(MicrophoneRoute.reason(AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue),
                       "neues_geraet")
        XCTAssertEqual(MicrophoneRoute.reason(AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue),
                       "geraet_weg")
        XCTAssertEqual(MicrophoneRoute.reason(nil), "unbekannt")
    }
}
