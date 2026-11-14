import Foundation

enum ListenGlowPhase: Equatable {
    case hidden
    case listening
}

enum ListenGlowPolicy {
    static func phase(foreground: Bool, sheetOpen: Bool, wakeWord: Bool,
                      voice: VoiceTranscriber.State) -> ListenGlowPhase {
        guard foreground, !sheetOpen, wakeWord, voice == .recording else { return .hidden }
        return .listening
    }
}

enum ListenLivePlan: Equatable {
    enum Mode: Equatable {
        case listen
        case conversation
    }

    enum Phase: Equatable {
        case armed
        case recording
        case processing
    }

    case hidden
    case visible(mode: Mode, phase: Phase, titleKey: String)

    static func plan(foreground: Bool, sheetOpen: Bool, listenMode: Bool, conversationMode: Bool,
                     microphoneLive: Bool, voice: VoiceTranscriber.State, working: Bool) -> ListenLivePlan {
        guard !foreground, !sheetOpen, listenMode || conversationMode, microphoneLive else { return .hidden }
        let mode: Mode = conversationMode ? .conversation : .listen
        switch voice {
        case .recording:
            return .visible(mode: mode, phase: .recording, titleKey: "listen_live_armed")
        case .processing:
            return .visible(mode: mode, phase: .processing, titleKey: "listen_live_processing")
        case .idle, .waiting:
            break
        }
        if working {
            return .visible(mode: mode, phase: .processing, titleKey: "listen_live_processing")
        }
        return .visible(mode: mode, phase: .armed, titleKey: "listen_live_armed")
    }
}
