@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import MediaPlayer
import Foundation

@MainActor
final class ProbeMusic: MusicSource {
    let service: MusicService
    private(set) var requests: [MusicRequest] = []
    private(set) var actions: [MusicAction] = []
    var isPlaying = false

    init(_ service: MusicService) {
        self.service = service
    }

    func play(_ request: MusicRequest) async -> MusicOutcome {
        requests.append(request)
        flowMark("MUSIK probe spielt nicht dienst=\(service.rawValue) \(request.stepWords)")
        guard request.wantsSomething else { return .resumed }
        return .playing(MusicPick(kind: request.kind, name: request.term, artist: request.artist))
    }

    func control(_ action: MusicAction) async -> MusicOutcome {
        actions.append(action)
        flowMark("MUSIK probe steuert nicht dienst=\(service.rawValue) aktion=\(action.rawValue)")
        return action == .resume ? .resumed : .controlled(action)
    }

    static func silent() -> [MusicService: any MusicSource] {
        [.appleMusic: ProbeMusic(.appleMusic), .spotify: ProbeMusic(.spotify)]
    }
}

@MainActor
enum DebugMusicProbe {
    private struct RouteCase {
        let text: String
        let wanted: SendStepKind
        var action: MusicAction?
        var kind: MusicKind?
        var service: MusicService?
        var exact = true
    }

    private static let routeCases = [
        RouteCase(text: "Spiel Musik", wanted: .music, action: .play),
        RouteCase(text: "Spiele meine Playlist Sport", wanted: .music, action: .play, kind: .playlist),
        RouteCase(text: "Spiel Songs von Adele", wanted: .music, action: .play, kind: .artist),
        RouteCase(text: "Spiel Hello von Adele auf Spotify", wanted: .music, action: .play, service: .spotify),
        RouteCase(text: "Spiel das Album 21 von Adele mit Apple Music", wanted: .music, action: .play, kind: .album,
                  service: .appleMusic),
        RouteCase(text: "Nächstes Lied", wanted: .music, action: .next),
        RouteCase(text: "Musik aus", wanted: .music, action: .pause),
        RouteCase(text: "Mach die Musik weiter", wanted: .music, action: .resume),
        RouteCase(text: "Wer singt Hello?", wanted: .chat, exact: false),
        RouteCase(text: "Wie lautet der Text von Bohemian Rhapsody?", wanted: .chat, exact: false),
        RouteCase(text: "Zeig mir Bilder von Adele", wanted: .gallery),
        RouteCase(text: "Wie spät ist es?", wanted: .clock),
        RouteCase(text: "Ruf Mama an", wanted: .call),
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.run(routeCases, file: "music_route.txt", view: view, log: "MUSIKROUTING fertig",
                             konfig: RouteSweep.konfig(view, routeCases.count),
                             sentence: { $0.text },
                             fits: { fitting($0, kind: $1.primary.stepKind, request: musicRequest($1)) },
                             line: { item, plan, pass, ms in
                                 "passt=\(pass) soll=\(item.wanted.rawValue) ist=\(plan.traceLine) "
                                     + "musik=\(musicRequest(plan)?.stepWords ?? "-") ms=\(ms) text=\(item.text)"
                             },
                             summe: { "richtig=\($0)/\(routeCases.count)" })
    }

    private static func musicRequest(_ plan: SendPlan) -> MusicRequest? {
        guard case .music(let request) = plan.primary.route else { return nil }
        return request
    }

    private static func fitting(_ item: RouteCase, kind: SendStepKind, request: MusicRequest?) -> Bool {
        guard item.wanted == .music else { return item.exact ? kind == item.wanted : kind != .music }
        guard let request else { return false }
        if let action = item.action, request.action != action { return false }
        if let wanted = item.kind, request.kind != wanted { return false }
        if let service = item.service, request.service != service { return false }
        return true
    }

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "music_flow.txt")
        let apple = ProbeMusic(.appleMusic)
        let spotify = ProbeMusic(.spotify)
        view.musicDesk.stand(in: [.appleMusic: apple, .spotify: spotify])
        let steps: [(String, MusicService, MusicAction)] = [("Spiele meine Playlist Sport", view.settings.music.service, .play),
                                                           ("Spiel Hello von Adele auf Spotify", .spotify, .play),
                                                           ("Nächstes Lied", .spotify, .next),
                                                           ("Musik aus", .spotify, .pause)]
        var right = 0
        for (text, service, action) in steps {
            let before = apple.requests.count + apple.actions.count + spotify.requests.count + spotify.actions.count
            let answer = await view.ask(text, fresh: true)
            let used = service == .spotify ? spotify : apple
            let lastAction = action == .play ? used.requests.last?.action : used.actions.last
            let after = apple.requests.count + apple.actions.count + spotify.requests.count + spotify.actions.count
            let fits = after == before + 1 && lastAction == action
            right += fits ? 1 : 0
            report.add("ABLAUF", "passt=\(fits) soll=\(service.rawValue)/\(action.rawValue) "
                       + "apple=\(apple.requests.map(\.stepWords) + apple.actions.map(\.rawValue)) "
                       + "spotify=\(spotify.requests.map(\.stepWords) + spotify.actions.map(\.rawValue)) "
                       + "antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 140))")
        }
        report.add("SUMME", "richtig=\(right)/\(steps.count)")
        flowLog.info("MUSIKABLAUF fertig")
    }

    static func library(_: ChatView) async {
        let report = SweepReport(file: "music_library.txt")
        #if !targetEnvironment(macCatalyst)
        let reader = MediaLibraryReader()
        let granted = await reader.access()
        report.add("ZUGRIFF", "erlaubt=\(granted)")
        guard granted else { return }
        for kind in MusicLibraryMatching.searchOrder {
            let started = ContinuousClock.now
            let entries = await reader.entries(of: [kind])
            let onMain = MediaLibraryIndex.entries(of: kind).count
            report.add("MEDIATHEK_\(kind.rawValue)", "anzahl=\(entries.count) hauptthread=\(onMain) "
                       + "ms=\(msOf(started.duration(to: .now))) erste=\(entries.prefix(3).map(\.name))")
        }
        report.add("MEDIATHEK_GESAMT", "alle_medien=\(MPMediaQuery().items?.count ?? -1) "
                   + "cloud_titel=\(MPMediaQuery.songs().items?.filter(\.isCloudItem).count ?? -1)")
        #else
        report.add("ZUGRIFF", "mac=keine_mediathek")
        #endif
        flowLog.info("MUSIKMEDIATHEK fertig")
    }

    static func catalog(_: ChatView) async {
        let report = SweepReport(file: "music_catalog.txt")
        let search = ITunesCatalogSearch()
        report.add("LAND", search.country)
        let samples = [MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song),
                       MusicRequest(action: .play, query: "Adele", kind: .artist),
                       MusicRequest(action: .play, query: "21", artist: "Adele", kind: .album)]
        for sample in samples {
            let started = ContinuousClock.now
            do {
                let found = try await search.find(sample)
                report.add("KATALOG_\(sample.kind.rawValue)", "titel=\(found?.storeIDs.count ?? 0) "
                           + "treffer=\(found.map { MusicAnswer.described($0.pick) } ?? "-") "
                           + "ms=\(msOf(started.duration(to: .now)))")
            } catch {
                report.addFailure("KATALOG_\(sample.kind.rawValue)", error)
            }
        }
        flowLog.info("MUSIKKATALOG fertig")
    }

    static func spotify(_: ChatView) async {
        let report = SweepReport(file: "spotify_check.txt")
        let link = SpotifyLink.shared
        report.add("SDK", "verfuegbar=\(SpotifyLink.isAvailable) client_id=\(link.isConfigured) "
                   + "angemeldet=\(link.signedIn)")
        #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
        guard let token = await link.accessToken() else {
            report.add("TOKEN", "keins")
            flowLog.info("SPOTIFYPRUEFUNG fertig")
            return
        }
        report.add("TOKEN", "vorhanden laenge=\(token.count)")
        do {
            let found = try await SpotifyWebClient().find(MusicRequest(action: .play, query: "Hello", artist: "Adele",
                                                                       kind: .song), token: token)
            report.add("SUCHE", "treffer=\(found.map { MusicAnswer.described($0.pick) } ?? "-") uri=\(found?.uri ?? "-")")
        } catch {
            report.addFailure("SUCHE", error)
        }
        #endif
        flowLog.info("SPOTIFYPRUEFUNG fertig")
    }

    static func mix(_: ChatView) async {
        let report = SweepReport(file: "music_mix.txt")
        report.add("VORGABE", RecordingSetup.preferred.map {
            "\($0.label) mischt=\($0.options.contains(.mixWithOthers)) senkt=\($0.options.contains(.duckOthers))"
        }.joined(separator: " | "))
        let voice = VoiceTranscriber()
        voice.start { _ in }
        try? await Task.sleep(for: .seconds(2))
        let session = AVAudioSession.sharedInstance()
        report.add("SITZUNG_BEI_AUFNAHME", "kategorie=\(session.category.rawValue) "
                   + "mischt=\(session.categoryOptions.contains(.mixWithOthers)) "
                   + "senkt=\(session.categoryOptions.contains(.duckOthers)) "
                   + "andere_audio=\(session.isOtherAudioPlaying) zustand=\(voice.state)")
        voice.cancel()
        flowLog.info("MUSIKMISCHUNG fertig")
    }
}
#endif
