@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
final class CuePreview: ObservableObject {
    private let tone: ChimeTone
    private var path = ""
    private var cue: ChosenCue?

    init(tone: ChimeTone) {
        self.tone = tone
    }

    func play(_ chosen: String) {
        path = chosen
        let cue = self.cue ?? ChosenCue(chosen: { [weak self] in self?.path ?? "" }, chime: ChimePlayer(tone: tone))
        self.cue = cue
        cue.play()
    }
}

struct SystemSoundGroup: Identifiable, Equatable {
    let folder: String
    let sounds: [SystemSound]

    var id: String { folder }

    static func grouped(_ sounds: [SystemSound], matching query: String) -> [SystemSoundGroup] {
        let wanted = TextFolding.fold(query)
        let kept = wanted.isEmpty ? sounds : sounds.filter { TextFolding.fold($0.name).contains(wanted) }
        var order: [String] = []
        var byFolder: [String: [SystemSound]] = [:]
        for sound in kept {
            if byFolder[sound.folder] == nil { order.append(sound.folder) }
            byFolder[sound.folder, default: []].append(sound)
        }
        return order.map { SystemSoundGroup(folder: $0, sounds: byFolder[$0] ?? []) }
    }
}

enum CueSoundLabel {
    static func name(of path: String) -> String {
        path.isEmpty ? L.t("sound_default") : SystemSoundCatalog.name(ofPath: path)
    }

    static func folder(_ folder: String) -> String {
        folder.isEmpty ? L.t("sound_folder_system") : folder
    }
}

struct CueSoundPicker: View {
    let title: String
    @Binding var selection: String
    @StateObject private var preview: CuePreview
    @State private var sounds: [SystemSound] = []
    @State private var loaded = false
    @State private var query = ""

    init(title: String, selection: Binding<String>, tone: ChimeTone) {
        self.title = title
        _selection = selection
        _preview = StateObject(wrappedValue: CuePreview(tone: tone))
    }

    var body: some View {
        List {
            Section {
                row(path: "", name: L.t("sound_default"))
            } footer: {
                Text(L.t("sound_preview_hint"))
            }
            ForEach(SystemSoundGroup.grouped(sounds, matching: query)) { group in
                Section(CueSoundLabel.folder(group.folder)) {
                    ForEach(group.sounds) { sound in row(path: sound.path, name: sound.name) }
                }
            }
            if loaded && sounds.isEmpty {
                Text(L.t("sound_none_found")).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: L.t("sound_search"))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sounds = await Offload.orNil { SystemSoundCatalog.live()?.sounds() ?? [] } ?? []
            loaded = true
        }
    }

    private func row(path: String, name: String) -> some View {
        Button(action: TapProbe.action({
            selection = path
            preview.play(path)
        })) {
            HStack {
                Text(verbatim: name).foregroundStyle(Color.primary)
                Spacer()
                if selection == path {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
