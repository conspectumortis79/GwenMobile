@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
final class TranscriptBox {
    var text: String?
}

@MainActor
enum DebugFeatureProbe {
    static func run(_ name: String, view: ChatView) async -> Bool {
        await view.withScreenAwake { await dispatch(name, view: view) }
    }

    private static func dispatch(_ name: String, view: ChatView) async -> Bool {
        switch name {
        case "webask": await webAsk(view)
        case "newsverify": await newsVerify(view)
        case "reviewmissing": await reviewMissing(view)
        case "sourcetrust": await sourceTrust(view)
        case "phototext": await photoText(view)
        case "historywipe": await historyWipe(view)
        case "micrec": await micRecord(view)
        case "ttsp": await ttsPlayback(view)
        case "micloop": await micLoop(view)
        case "calwrite": await calendarWrite()
        case "calguard": await calendarGuard()
        case "calflow": await calendarFlow(view)
        case "shareprobe": await shareProbe(view)
        case "undoflow": await undoFlow(view)
        case "langprobe": await languageFlow(view)
        case "transprobe": await DebugTranslationProbe.run(view)
        case "inputenter": await inputReturnSends(view)
        case "livespeech": await liveSpeech(view)
        case "longenter": await longInputSends(view)
        case "keychainprobe": await keychainProbe()
        case "filepicker": await filePickerProbe(view)
        #if targetEnvironment(macCatalyst)
        case "macpresence": await macPresenceProbe()
        #endif
        case "transremember": await translationRemembered(view)
        case "thinkprobe": await thinkingFlow(view)
        case "shortcutprobe": await shortcutFlow(view)
        case "tlsretry": await tlsRetry()
        case "voiceabort": await voiceAbort(view)
        case "conversation": await conversationEcho(view)
        case "conversationbarge": await conversationBargeIn(view)
        case "conversationsilence": await conversationSilence(view)
        case "conversationturn": await conversationTurn(view)
        case "conversationcancelword": await conversationCancelWord(view)
        case "listencancel": await listenCancelWord(view)
        case "conversationcleanup": await conversationCleanup(view)
        case "conversationkeep": await conversationKeep(view)
        case "modeflip": await modeFlip(view)
        case "toolprobe": await toolProbe(view)
        case "routeprobe": await routeProbe(view)
        case "placeprobe": await placeProbe(view)
        case "routeflow": await routeFlow(view)
        case "placesdemo": await placesDemo(view)
        case "mapnearby": await mapNearby(view)
        case "mapplace": await mapPlace(view)
        case "chaterror": await chatError(view)
        case "providerprobe": await ProviderProbe.run(view)
        case "localprobe": await DebugLocalProbe.run(view)
        case "localquestion": await DebugLocalQuestionProbe.run(view)
        case "hfprobe": await DebugHuggingFaceProbe.run()
        case "deepseekprobe": await ProviderProbe.runDeepSeek(view)
        case "speechfile": await SpeechFileProbe.run(view)
        case "alertprobe": await alertProbe(view)
        case "retryprobe": await retryProbe()
        case "picprobe": await DebugPictureSearchProbe.pictureProbe()
        case "picguard": await DebugPictureSearchProbe.routeGuard(view)
        case "piceditcontext": await DebugPictureSearchProbe.editContext(view)
        case "piceditroute": await DebugPictureSearchProbe.editRoute(view)
        case "pichonesty": await DebugPictureSearchProbe.honesty(view)
        case "picflip": await DebugPictureSearchProbe.flip(view)
        case "picflow": await DebugPictureSearchProbe.flow(view)
        case "picsdemo": await DebugPictureSearchProbe.demo(view)
        case "piclayout": await DebugPictureLayoutProbe.gallery(view)
        case "pricescan": await DebugPriceProbe.priceScan(view)
        case "pricewatch": await DebugPriceWatchProbe.run(view)
        case "daybriefing": await DebugDayBriefingProbe.run(view)
        case "cancelrun": await DebugCancelProbe.run(view)
        case "priceguard": await DebugPriceProbe.routeGuard(view)
        case "pricepath": await DebugPriceProbe.pricePath(view)
        case "pricecapsule": await DebugPriceProbe.capsule(view)
        case "priceregion": await DebugPriceProbe.region(view)
        case "pricetrigger": await DebugPriceProbe.trigger(view)
        case "pricebadge": await DebugPriceProbe.badge(view)
        default: return false
        }
        return true
    }

    static func cleanUpProbeConversations(_ view: ChatView, keeping known: Set<UUID>,
                                          restore previous: UUID? = nil) -> Int {
        var removed = 0
        for conversation in view.store.conversations where !known.contains(conversation.id) {
            if view.store.removeConversation(conversation.id) != nil { removed += 1 }
        }
        if let previous, view.store.conversations.contains(where: { $0.id == previous }) {
            view.store.currentID = previous
        }
        return removed
    }

    static func freshAsk(_ view: ChatView, _ sentence: String, log: String,
                         resetPlan: Bool = false) async -> [ChatMessage] {
        view.store.newConversation()
        view.pendingImages = []
        view.pendingFiles = []
        if resetPlan { view.probeLastPlan = nil }
        let before = view.store.current?.messages.count ?? 0
        view.input = sentence
        flowMark(log)
        await view.send()
        return Array((view.store.current?.messages ?? []).dropFirst(before))
            .filter { $0.role == .assistant }
    }

    static func tomorrowAt(_ hour: Int, calendar: Calendar = .current, now: Date = Date()) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
#endif
