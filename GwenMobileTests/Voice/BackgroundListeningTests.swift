@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

@MainActor
final class FakeMicrophoneTap: ResumableAudioFeeding {
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var resumes = 0
    private(set) var reconnects = 0
    private(set) var voiceProcessing = false
    var isVoiceProcessing: Bool { voiceProcessing }
    var isFlowing = false
    var resumeFails = false
    var reconnectFails = false
    private var deliver: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        starts += 1
        isRunning = true
        isFlowing = true
        self.deliver = deliver
    }

    func stop() {
        stops += 1
        isRunning = false
        isFlowing = false
        deliver = nil
    }

    func resume() async throws {
        resumes += 1
        if resumeFails { throw APIError(message: "!rec") }
        isFlowing = true
    }

    func reconnect() async throws {
        reconnects += 1
        if reconnectFails { throw APIError(message: "format") }
        isFlowing = true
    }

    func setVoiceProcessing(_ enabled: Bool) async throws {
        voiceProcessing = enabled
    }

    func hear(_ buffer: AVAudioPCMBuffer) { deliver?(buffer) }
}

@MainActor
final class BlockingMicrophoneTap: ResumableAudioFeeding {
    private(set) var isRunning = false
    private(set) var isFlowing = false
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var waiting = false
    private var startContinuation: CheckedContinuation<Void, Error>?

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        starts += 1
        waiting = true
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
        isRunning = true
        isFlowing = true
    }

    func release() {
        waiting = false
        startContinuation?.resume()
        startContinuation = nil
    }

    func stop() {
        stops += 1
        isRunning = false
        isFlowing = false
    }

    func resume() async throws { isFlowing = true }
    func reconnect() async throws { isFlowing = true }
}

@MainActor
final class FakeDisruptions: AudioDisruptionWatching {
    private(set) var watching = false
    private var handler: (@MainActor (AudioDisruption) async -> Void)?

    func start(_ handler: @escaping @MainActor (AudioDisruption) async -> Void) {
        watching = true
        self.handler = handler
    }

    func stop() {
        watching = false
        handler = nil
    }

    func send(_ disruption: AudioDisruption) async { await handler?(disruption) }
}

@MainActor
final class FakeHeadsets: HeadsetHandling {
    private(set) var starts = 0
    private(set) var stops = 0

    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
final class LossCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

@MainActor
final class HeldMicrophoneTests: XCTestCase {
    private let silence = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!,
                                           frameCapacity: 16)!

    private func sink(_ label: String, into heard: LockedValue<[String]>) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { _ in heard.mutate { $0.append(label) } }
    }

    private func buffer(peak: Float) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!,
                                      frameCapacity: 4)!
        buffer.frameLength = 4
        buffer.floatChannelData![0][0] = peak
        buffer.floatChannelData![0][1] = -peak
        buffer.floatChannelData![0][2] = peak
        buffer.floatChannelData![0][3] = 0
        return buffer
    }

    private func heldMicrophone(lost: LossCounter? = nil) async throws -> (HeldMicrophone, FakeMicrophoneTap, FakeDisruptions) {
        let tap = FakeMicrophoneTap()
        let disruptions = FakeDisruptions()
        let microphone = HeldMicrophone(tap: tap, disruptions: disruptions, headsets: FakeHeadsets())
        microphone.hold(onLoss: { lost?.bump() })
        try await microphone.start(deliver: { _ in })
        return (microphone, tap, disruptions)
    }

    func testQuietMicrophoneAudioIsLiftedBeforeItReachesTheRequest() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        let heard = LockedValue<Float>(0)
        try await microphone.start(deliver: { buffer in
            heard.set(buffer.floatChannelData![0][0])
        })
        tap.hear(buffer(peak: 0.01))
        XCTAssertEqual(heard.current, 0.12, accuracy: 0.0001)
        XCTAssertEqual(microphone.currentPeak, 0.01, accuracy: 0.0001)
        XCTAssertEqual(microphone.buffersDelivered, 1)
    }

    func testTheBoostCanBeSwitchedOffForTheMicrophone() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets(),
                                        boost: .off)
        let heard = LockedValue<Float>(0)
        try await microphone.start(deliver: { buffer in
            heard.set(buffer.floatChannelData![0][0])
        })
        tap.hear(buffer(peak: 0.01))
        XCTAssertEqual(heard.current, 0.01, accuracy: 0.0001)
    }

    func testTheMicrophoneForwardsTheVoiceProcessingSwitch() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        XCTAssertFalse(microphone.isVoiceProcessing)
        try await microphone.setVoiceProcessing(true)
        XCTAssertTrue(tap.voiceProcessing)
        XCTAssertTrue(microphone.isVoiceProcessing)
        try await microphone.setVoiceProcessing(false)
        XCTAssertFalse(tap.voiceProcessing)
    }

    func testWithoutHoldTheMicrophoneEndsWithTheSession() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        try await microphone.start(deliver: { _ in })
        XCTAssertTrue(microphone.isLive)
        XCTAssertTrue(microphone.isRunning)
        microphone.stop()
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(microphone.isLive)
    }

    func testAHeldMicrophoneKeepsRunningBetweenTwoRequests() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        let heard = LockedValue<[String]>([])
        microphone.hold(onLoss: {})
        try await microphone.start(deliver: sink("erste", into: heard))
        tap.hear(silence)
        microphone.stop()
        XCTAssertEqual(tap.stops, 0, "zwischen zwei Anfragen darf das Mikrofon nicht aus")
        XCTAssertTrue(microphone.isLive)
        XCTAssertFalse(microphone.isRunning, "ohne Erkennung ist niemand angehängt")
        tap.hear(silence)
        try await microphone.start(deliver: sink("zweite", into: heard))
        tap.hear(silence)
        XCTAssertEqual(tap.starts, 1, "die zweite Anfrage hängt sich an das laufende Mikrofon")
        XCTAssertEqual(heard.current, ["erste", "zweite"], "Ton ohne Erkennung wird verworfen")
        XCTAssertEqual(microphone.buffersDelivered, 3)
    }

    func testReleasingTurnsTheMicrophoneOffOnceNoRequestUsesIt() async throws {
        let tap = FakeMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        microphone.hold(onLoss: {})
        try await microphone.start(deliver: { _ in })
        microphone.release()
        XCTAssertEqual(tap.stops, 0, "eine laufende Anfrage darf zu Ende hören")
        microphone.stop()
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(microphone.isLive)
        XCTAssertFalse(microphone.isHeld)
    }

    func testASecondStartWaitsForTheRunningStart() async throws {
        let tap = BlockingMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        let first = Task { try await microphone.start(deliver: { _ in }) }
        while !tap.waiting { await Task.yield() }
        let second = Task { try await microphone.start(deliver: { _ in }) }
        await Task.yield()
        tap.release()
        try await first.value
        try await second.value
        XCTAssertEqual(tap.starts, 1)
        XCTAssertTrue(microphone.isLive)
    }

    func testADetachedStartStopsTheTapAfterTheStartReturns() async throws {
        let tap = BlockingMicrophoneTap()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: FakeHeadsets())
        let task = Task { try await microphone.start(deliver: { _ in }) }
        while !tap.waiting { await Task.yield() }
        microphone.stop()
        tap.release()
        try await task.value
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(microphone.isLive)
    }

    func testTheHeadsetHandoverRunsExactlyAsLongAsTheMicrophone() async throws {
        let tap = FakeMicrophoneTap()
        let headsets = FakeHeadsets()
        let microphone = HeldMicrophone(tap: tap, disruptions: FakeDisruptions(), headsets: headsets)
        microphone.hold(onLoss: {})
        try await microphone.start(deliver: { _ in })
        microphone.stop()
        try await microphone.start(deliver: { _ in })
        XCTAssertEqual(headsets.starts, 1, "zwischen zwei Anfragen läuft die Übergabe weiter")
        XCTAssertEqual(headsets.stops, 0)
        microphone.stop()
        microphone.release()
        XCTAssertEqual(headsets.stops, 1, "ohne Mikrofon gibt es nichts mehr zu übergeben")
    }

    func testAnEndedInterruptionResumesTheMicrophone() async throws {
        let lost = LossCounter()
        let (microphone, tap, disruptions) = try await heldMicrophone(lost: lost)
        XCTAssertTrue(disruptions.watching)
        await disruptions.send(.began)
        tap.isFlowing = false
        await disruptions.send(.ended)
        XCTAssertEqual(tap.resumes, 1)
        XCTAssertEqual(tap.reconnects, 0, "nach einer Unterbrechung muss die Sitzung wieder aktiviert werden")
        XCTAssertTrue(microphone.isLive)
        XCTAssertEqual(lost.count, 0)
    }

    func testAChangedDeviceOnlyReconnectsTheTapWithoutTouchingTheSession() async throws {
        let (microphone, tap, disruptions) = try await heldMicrophone()
        tap.isFlowing = false
        await disruptions.send(.reconfigured)
        XCTAssertEqual(tap.reconnects, 1)
        XCTAssertEqual(tap.resumes, 0, "ein neues Sitzungs-Setup würde den Ton wieder auf das alte Gerät ziehen")
        XCTAssertTrue(microphone.isLive)
    }

    func testAFailedReconnectFallsBackToAFullResume() async throws {
        let lost = LossCounter()
        let (microphone, tap, disruptions) = try await heldMicrophone(lost: lost)
        tap.isFlowing = false
        tap.reconnectFails = true
        await disruptions.send(.reconfigured)
        XCTAssertEqual(tap.reconnects, 1)
        XCTAssertEqual(tap.resumes, 1)
        XCTAssertEqual(lost.count, 0)
        tap.isFlowing = false
        tap.resumeFails = true
        await disruptions.send(.reconfigured)
        XCTAssertEqual(lost.count, 1, "wenn beides scheitert, ist das Mikrofon verloren")
        XCTAssertFalse(microphone.isLive)
    }

    func testAFlowingMicrophoneIgnoresEndsThatAreNotItsOwn() async throws {
        let tap = FakeMicrophoneTap()
        let disruptions = FakeDisruptions()
        let microphone = HeldMicrophone(tap: tap, disruptions: disruptions, headsets: FakeHeadsets())
        try await microphone.start(deliver: { _ in })
        await disruptions.send(.ended)
        XCTAssertEqual(tap.resumes, 0)
    }

    func testAMicrophoneIOSRefusesToResumeIsReportedLost() async throws {
        let tap = FakeMicrophoneTap()
        let disruptions = FakeDisruptions()
        let microphone = HeldMicrophone(tap: tap, disruptions: disruptions, headsets: FakeHeadsets())
        let lost = LossCounter()
        let heard = LockedValue<[String]>([])
        microphone.hold(onLoss: { lost.bump() })
        try await microphone.start(deliver: sink("nach_verlust", into: heard))
        tap.isFlowing = false
        tap.resumeFails = true
        await disruptions.send(.ended)
        XCTAssertEqual(lost.count, 1)
        XCTAssertFalse(microphone.isLive)
        XCTAssertFalse(microphone.isRunning)
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(disruptions.watching)
        XCTAssertTrue(microphone.isHeld, "der Zuhörmodus bleibt an und hört im Vordergrund wieder zu")
        try await microphone.start(deliver: sink("neu", into: heard))
        tap.hear(silence)
        XCTAssertEqual(tap.starts, 2, "im Vordergrund startet das Mikrofon neu")
        XCTAssertEqual(heard.current, ["neu"])
    }
}

final class AudioDisruptionTests: XCTestCase {
    func testTheInterruptionTypeIsReadFromTheNotification() {
        XCTAssertEqual(AudioDisruption.interruption(AVAudioSession.InterruptionType.began.rawValue), .began)
        XCTAssertEqual(AudioDisruption.interruption(AVAudioSession.InterruptionType.ended.rawValue), .ended)
        XCTAssertNil(AudioDisruption.interruption(nil))
        XCTAssertNil(AudioDisruption.interruption(99))
    }
}

final class AnswerAnnouncementTests: XCTestCase {
    func testInTheForegroundOnlyTheReadAloudSettingDecides() {
        XCTAssertEqual(AnswerAnnouncement.plan(readAloud: false, foreground: true, listening: true),
                       AnswerAnnouncement(speaks: false, notifies: false))
        XCTAssertEqual(AnswerAnnouncement.plan(readAloud: true, foreground: true, listening: true),
                       AnswerAnnouncement(speaks: true, notifies: false))
    }

    func testAnAnswerToTheListeningModeInTheBackgroundIsReadAloudAndNotified() {
        XCTAssertEqual(AnswerAnnouncement.plan(readAloud: false, foreground: false, listening: true),
                       AnswerAnnouncement(speaks: true, notifies: true))
    }

    func testWithoutTheListeningModeTheBackgroundChangesNothing() {
        XCTAssertEqual(AnswerAnnouncement.plan(readAloud: false, foreground: false, listening: false),
                       AnswerAnnouncement(speaks: false, notifies: false))
        XCTAssertEqual(AnswerAnnouncement.plan(readAloud: true, foreground: false, listening: false),
                       AnswerAnnouncement(speaks: true, notifies: false))
    }
}

@MainActor
final class ListenNoticeTests: GwenTestCase {
    func testTheStopNoticeAsksToOpenTheAppAndReplacesItsPredecessor() {
        let notice = ListenNotice.stopped
        XCTAssertEqual(notice.id, ListenNotice.stoppedID)
        XCTAssertTrue(notice.audible)
        XCTAssertTrue(notice.body.contains("GwenMobile"))
    }

    func testTheAnswerNoticeCarriesTheSpokenTextOnly() throws {
        let notice = try XCTUnwrap(ListenNotice.answer("**Tokio** liegt 7 Stunden vorn [1].\n\nMehr dazu", id: "a"))
        XCTAssertEqual(notice.body, "Tokio liegt 7 Stunden vorn. Mehr dazu")
        XCTAssertFalse(notice.audible, "die Antwort wird vorgelesen, ein Signalton wäre doppelt")
        XCTAssertNil(ListenNotice.answer("[1]"))
    }

    func testALongAnswerIsShortenedForTheNotification() throws {
        let notice = try XCTUnwrap(ListenNotice.answer(String(repeating: "Wort ", count: 400)))
        XCTAssertEqual(notice.body.count, ListenNotice.answerLimit)
    }
}

final class HeadsetHandoverPolicyTests: XCTestCase {
    private let airPods = "airpods-uid"
    private let sony = "sony-uid"
    private let phone = "iphone-mic"

    private func change(left: Bool = false, arrived: Bool = false, previous: Set<String> = [],
                        current: Set<String> = [], available: Set<String>) -> RouteChange {
        RouteChange(deviceLeft: left, deviceArrived: arrived, previousBluetooth: previous, currentBluetooth: current,
                    available: available)
    }

    func testAHeadsetTakenByAnotherDeviceIsReleasedEvenIfAnotherHeadsetTakesOver() {
        var policy = HeadsetHandoverPolicy()
        XCTAssertEqual(policy.decide(change(left: true, previous: [airPods], current: [sony], available: [phone, sony])),
                       .yield, "der Mac hat die AirPods, der Sony übernimmt: das iPhone nimmt sein eigenes Mikrofon")
        XCTAssertEqual(policy.yielded, [airPods])
        XCTAssertEqual(policy.missing, [airPods])
    }

    func testAnotherHeadsetInTheRouteIsLeftAloneWhileAReleaseRuns() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone, sony]))
        XCTAssertEqual(policy.decide(change(current: [sony], available: [phone, sony])), .none,
                       "der Sony übernimmt: das iPhone darf ihn nutzen, nur die AirPods bleiben bei ihrem Gerät")
        XCTAssertEqual(policy.decide(change(available: [phone, sony])), .none, "schon auf dem iPhone: nichts zu tun")
    }

    func testAReleasedHeadsetThatWasGoneAndComesBackIsPreferredAgain() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone]))
        XCTAssertEqual(policy.missing, [airPods])
        XCTAssertEqual(policy.decide(change(arrived: true, available: [phone, airPods])),
                       .reclaim(preferring: [airPods]), "die AirPods waren weg und sind wieder da")
        XCTAssertTrue(policy.yielded.isEmpty)
        XCTAssertTrue(policy.missing.isEmpty)
    }

    func testAReleasedHeadsetThatStaysListedIsNotGrabbedBack() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone, airPods]))
        XCTAssertEqual(policy.decide(change(arrived: true, available: [phone, airPods])), .none,
                       "iOS meldet die gelisteten AirPods neu, während der Mac sie noch nutzt")
        XCTAssertEqual(policy.yielded, [airPods])
    }

    func testAnotherHeadsetOnlyListedWithoutAnArrivalReportKeepsTheRelease() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone]))
        XCTAssertEqual(policy.decide(change(current: [sony], available: [phone, sony])), .none)
        XCTAssertEqual(policy.yielded, [airPods])
    }

    func testBluetoothWithoutANewDeviceIsStillPushedBackToThePhone() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone, airPods]))
        XCTAssertEqual(policy.decide(change(current: [airPods], available: [phone, airPods])), .yield,
                       "iOS legt den Ton von selbst zurück, ohne dass ein Gerät neu kam")
    }

    func testAnUnreadableListOfInputsDoesNotMarkAReleasedHeadsetMissing() {
        var policy = HeadsetHandoverPolicy()
        _ = policy.decide(change(left: true, previous: [airPods], available: [phone, airPods]))
        XCTAssertEqual(policy.decide(change(available: [])), .none)
        XCTAssertTrue(policy.missing.isEmpty, "eine leere Liste ist keine Messung")
    }

    func testWithoutADepartureNothingIsTouched() {
        var policy = HeadsetHandoverPolicy()
        XCTAssertEqual(policy.decide(change(previous: [airPods], current: [airPods], available: [phone, airPods])),
                       .none)
        XCTAssertEqual(policy.decide(change(left: true, available: [phone])), .none,
                       "ein kabelgebundenes Gerät geht, kein Bluetooth betroffen")
    }
}

final class AudioLevelMeterTests: XCTestCase {
    private func buffer(peak: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        for index in 0..<160 { buffer.floatChannelData![0][index] = index == 80 ? -peak : peak / 10 }
        return buffer
    }

    func testDecibelsAreMeasuredFromTheLoudestSample() {
        XCTAssertEqual(AudioLevelMeter.decibels(1), 0)
        XCTAssertEqual(AudioLevelMeter.decibels(0.1), -20)
        XCTAssertEqual(AudioLevelMeter.decibels(0), AudioLevelMeter.floor, "reine Stille")
    }

    func testTheLoudestPeakOfEachWindowIsReportedOnce() {
        let reported = LockedValue<[Int]>([])
        let meter = AudioLevelMeter(report: { value in reported.mutate { $0.append(value) } })
        let start = Date(timeIntervalSince1970: 0)
        meter.measure(buffer(peak: 0.01), at: start)
        meter.measure(buffer(peak: 0.5), at: start.addingTimeInterval(4))
        XCTAssertTrue(reported.current.isEmpty, "vor Ablauf des Fensters wird nichts gemeldet")
        meter.measure(buffer(peak: 0.01), at: start.addingTimeInterval(AudioLevelMeter.window))
        XCTAssertEqual(reported.current, [-6])
        meter.measure(buffer(peak: 0.01), at: start.addingTimeInterval(AudioLevelMeter.window * 1.5))
        meter.measure(buffer(peak: 0), at: start.addingTimeInterval(AudioLevelMeter.window * 2))
        XCTAssertEqual(reported.current, [-6, -40], "das neue Fenster beginnt ohne die alte Spitze")
    }
}
