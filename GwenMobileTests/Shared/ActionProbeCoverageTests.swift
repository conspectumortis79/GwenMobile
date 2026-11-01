@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ActionProbeCoverageTests: GwenTestCase {
    private func cleaner(_ store: ChatStore) -> HistoryCleaner {
        HistoryCleaner(store: store, media: store.media, documents: store.documents,
                       exports: store.exports, feed: store.images)
    }

    private func drainAll() async throws {
        runProbedActions()
        try await settle(250)
        runProbedActions()
        try await settle(250)
        runProbedActions()
    }

    private func scrollToEnd(_ controller: UIHostingController<AnyView>) {
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView {
                let bottom = max(0, scroll.contentSize.height - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(controller.view)
        controller.view.layoutIfNeeded()
    }

    func testSmokeTheSettingsViewsRender() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        MockHTTP.install(MockHTTP.defaultHandler)
        defer { MockHTTP.uninstall() }
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedKey = settings.key(for: provider)
        settings.setKey("probe-settings-key", for: provider)
        defer { settings.setKey(savedKey, for: provider) }
        let store = stagedStore("probe-settings").store
        let clean = cleaner(store)
        await store.memory.add(text: "mag Tee", category: .likes, source: .explicit)
        let view = SettingsView()
        view.showMemory = true
        view.showPriceWatch = true
        view.confirmDeleteMemory = true
        view.confirmDeleteAll = true
        view.testResult = "fertig"
        let controller = mountView(view.environmentObject(store).environmentObject(clean),
                                   size: CGSize(width: 390, height: 1600))
        try await settleHosted(controller, milliseconds: 600)
        scrollToEnd(controller)
        var result: String?
        let binding = Binding(get: { result }, set: { result = $0 })
        let models = mountView(Form { ModelsSettingsView(testResult: binding) }
            .environmentObject(store).environmentObject(clean),
                               size: CGSize(width: 390, height: 900))
        try await settleHosted(models, milliseconds: 500)
        dismissPresentedSheets()
    }

    func testSmokeTheMemoryViewsDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let store = stagedStore("probe-memory").store
        Presenter.hostOverride = nil
        _ = await store.memory.add(text: "mag Tee", category: .likes, source: .explicit)
        let entry = MemoryEntry(text: "mag Tee", category: .likes)
        let list = mountView(NavigationStack { MemoryView().environmentObject(store) },
                             size: CGSize(width: 390, height: 900))
        try await settleHosted(list, milliseconds: 500)
        scrollToEnd(list)

        let editor = mountView(NavigationStack { MemoryEditorSheet(entry: entry).environmentObject(store) },
                               size: CGSize(width: 390, height: 900))
        try await settleHosted(editor, milliseconds: 500)
        scrollToEnd(editor)

        let emptyEditor = mountView(NavigationStack { MemoryEditorSheet(entry: nil).environmentObject(store) },
                                    size: CGSize(width: 390, height: 900))
        try await settleHosted(emptyEditor, milliseconds: 400)

        dismissPresentedSheets()
    }

    func testSmokeThePriceViewsDrain() async throws {
        let store = stagedStore("probe-prices").store
        _ = await store.watches.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                       currencyCode: "EUR", regionCode: "DE")
        let view = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                             size: CGSize(width: 390, height: 900))
        try await settleHosted(view, milliseconds: 600)
        scrollToEnd(view)
        try await drainAll()
        let watch = PriceWatch(terms: ["PlayStation 5"], goal: 400, wording: "PS5")
        let card = mountView(PriceWatchCardView(ref: PriceWatchRef(watch: watch)),
                             size: CGSize(width: 390, height: 320))
        try await settleHosted(card, milliseconds: 300)
        try await drainAll()
        dismissPresentedSheets()
    }

    func testSmokeThePictureViewsDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let store = stagedStore("probe-pictures").store
        let att = Attachment(file: store.media.storeImageData(Data([1, 2, 3])) ?? "fehlt.jpg")
        let picture = WebPicture(file: att.file, pageURL: "tel:0171", fullURL: "tel:0172",
                                 title: "Bild", domain: "example.com")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let selection = GallerySelection()
        selection.begin(owner: UUID())
        selection.toggle(picture.file)
        let galleryView = PictureGalleryView(gallery: gallery, owner: selection.owner,
                                             onOpen: { _ in }, onOpenSource: { _ in },
                                             onOpenOriginal: { _ in }, onMore: {},
                                             onShare: { _ in }, onSave: { _ in })
            .environmentObject(store.images).environmentObject(selection)
            .environmentObject(GalleryOperation())
        let galleryHost = mountView(galleryView, size: CGSize(width: 390, height: 900))
        try await settleHosted(galleryHost, milliseconds: 400)
        try await drainAll()
        if let target = ImagePreviewTarget(tappedFile: picture.file, files: [picture.file]) {
            let viewer = mountView(ImageViewerView(target: target, reader: store.media),
                                   size: CGSize(width: 390, height: 900))
            try await settleHosted(viewer, milliseconds: 400)
            try await drainAll()
        }
        dismissPresentedSheets()
    }

    func testSmokeTheBriefingViewsDrain() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let ref = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
        let card = mountView(DayBriefingCard(ref: ref, onDay: { _ in }, onSpeak: {}, onNotify: {},
                                             onOpenEvent: { _ in }),
                             size: CGSize(width: 390, height: 700))
        try await settleHosted(card, milliseconds: 400)
        try await drainAll()
        let section = mountView(Form { DayBriefingSettingsSection(settings: AppSettings.shared) },
                                size: CGSize(width: 390, height: 900))
        try await settleHosted(section, milliseconds: 400)
        try await drainAll()
        dismissPresentedSheets()
    }

    func testSmokeTheMusicViewDrains() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let music = mountView(Form { MusicSettingsSection(settings: AppSettings.shared) },
                              size: CGSize(width: 390, height: 700))
        try await settleHosted(music, milliseconds: 400)
        try await drainAll()
        dismissPresentedSheets()
    }

    func testSmokeTheCuePickerDrains() async throws {
        var cue = ""
        let cueBinding = Binding(get: { cue }, set: { cue = $0 })
        let picker = mountView(NavigationStack { CueSoundPicker(title: L.t("sent_sound"), selection: cueBinding,
                                                                tone: .sent) },
                               size: CGSize(width: 390, height: 900))
        try await settleHosted(picker, milliseconds: 500)
        scrollToEnd(picker)
        try await drainAll()
        dismissPresentedSheets()
    }

}
