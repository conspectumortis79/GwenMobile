@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct MusicSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var spotify = SpotifyLink.shared

    var body: some View {
        Section {
            Picker(L.t("music_service"), selection: $settings.music.service) {
                ForEach(MusicService.allCases, id: \.self) { service in
                    Text(verbatim: service.label).tag(service)
                }
            }
            if SpotifyLink.isAvailable {
                LabeledContent(L.t("spotify_client_id")) {
                    TextField("", text: $settings.music.spotifyClientID)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Spotify") {
                    Text(L.t(spotify.signedIn ? "spotify_connected" : "spotify_not_connected"))
                        .foregroundStyle(.secondary)
                }
                Button(L.t(spotify.signedIn ? "spotify_disconnect" : "spotify_connect"), action: TapProbe.action({
                    if spotify.signedIn { spotify.signOut() } else { spotify.signIn() }
                }))
                .disabled(!spotify.signedIn && SpotifyConfig.cleaned(settings.music.spotifyClientID).isEmpty)
            } else {
                Text(L.t("spotify_unavailable")).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L.t("music_section"))
        } footer: {
            Text(L.fmt2("music_footer", SpotifyConfig.redirectURI, SpotifyConfig.bundleID))
                .textSelection(.enabled)
        }
    }
}
