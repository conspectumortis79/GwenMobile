#if DEBUG
import SwiftUI
import UIKit

let flowTestBigImage = "img_0B85747A-BAA.jpg"
let flowTestEditImage = "img_7924D952-6BF.jpg"
let flowTestRounds = 3

enum DebugLaunchTrigger {
    static let flowTestFlag = "-gwenflowtest"

    static func flowTestName(arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flowTestFlag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

extension ChatView {
    func lastImageCandidate() -> Attachment? {
        ConversationMemory.rememberedImages(from: store.current?.messages ?? []).last
    }

    func flowTestPicture(named file: String = flowTestBigImage) async -> UIImage? {
        guard let stored = store.media.data(named: file) else {
            flowLog.error("TEST no big image file")
            return nil
        }
        guard let picture = await Task.detached(priority: .userInitiated, operation: {
            MediaStore.thumbnail(stored, maxPixel: ImagePolicy.uploadMaxPixel)
        }).value else {
            flowLog.error("TEST no thumbnail")
            return nil
        }
        return picture
    }

    func runFlowTest(_ name: String) async {
        if await DebugFeatureProbe.run(name, view: self) { return }
        if name == "sweep" {
            await runSweep()
            return
        }
        if name == "picsweep" {
            await runPictureSweep()
            return
        }
        if name == "chartprobe" {
            await runChartProbe()
            return
        }
        if name == "chartguard" {
            await runChartGuardProbe()
            return
        }
        if name == "searchonce" {
            await runSearchOnceProbe()
            return
        }
        if name == "exportprobe" {
            await runExportProbe()
            return
        }
        if name == "capsprobe" {
            await runCapabilityProbe()
            return
        }
        if name == "viewerprobe" {
            await runViewerProbe()
            return
        }
        if name == "airdropprobe" {
            await runAirDropProbe()
            return
        }
        if name == "menushow" {
            attachMenu = true
            return
        }
        let all = store.conversations.flatMap { c in c.messages.flatMap(\.pictures) }
        if name == "typetest" || name == "scrolltest" {
            UIApplication.shared.isIdleTimerDisabled = true
            guard let conv = store.conversations.first(where: { c in
                c.messages.contains { m in (m.outImages ?? []).contains { $0.file == flowTestBigImage } }
            }) else { flowLog.error("TEST no big conv"); UIApplication.shared.isIdleTimerDisabled = false; return }
            store.currentID = conv.id
            try? await Task.sleep(for: .milliseconds(1500))
            if name == "typetest" {
                inputFocused = true
                for round in 1...flowTestRounds {
                    flowLog.info("TYPETEST round=\(round) begin")
                    let t0 = ContinuousClock.now
                    input = ""
                    for ch in "Bitte realitätsnaher mit Bränden und mehr Kontrast".unicodeScalars {
                        input.append(Character(ch))
                        try? await Task.sleep(for: .milliseconds(70))
                    }
                    flowLog.info("TYPETEST round=\(round) done ms=\(msOf(t0.duration(to: .now)))")
                    try? await Task.sleep(for: .milliseconds(1200))
                }
                input = ""
            } else {
                guard let proxy = scrollProxy else { flowLog.error("SCROLLTEST no proxy"); UIApplication.shared.isIdleTimerDisabled = false; return }
                let ids = conv.messages.map { "msg-\($0.id.uuidString)" }
                for round in 1...flowTestRounds {
                    flowLog.info("SCROLLTEST round=\(round) begin")
                    let t0 = ContinuousClock.now
                    for id in ids.reversed() {
                        proxy.scrollTo(id, anchor: .center)
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                    for id in ids {
                        proxy.scrollTo(id, anchor: .center)
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                    flowLog.info("SCROLLTEST round=\(round) done ms=\(msOf(t0.duration(to: .now)))")
                }
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowLog.info("\(name, privacy: .public) all done")
            return
        }
        if name == "camtypetest" {
            UIApplication.shared.isIdleTimerDisabled = true
            guard let conv = store.conversations.first(where: { $0.messages.count > 20 }) else { flowLog.error("TEST no heavy conv"); UIApplication.shared.isIdleTimerDisabled = false; return }
            store.currentID = conv.id
            try? await Task.sleep(for: .milliseconds(2000))
            guard let img = await flowTestPicture() else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            for i in 1...flowTestRounds {
                flowLog.info("CAMTYPE run=\(i) begin")
                let t0 = ContinuousClock.now
                inputFocused = true
                try? await Task.sleep(for: .milliseconds(900))
                pendingImages = [(image: img, file: nil)]
                try? await Task.sleep(for: .milliseconds(1500))
                for ch in "Mache das Bild etwas heller".unicodeScalars {
                    input.append(Character(ch))
                    try? await Task.sleep(for: .milliseconds(90))
                }
                flowLog.info("CAMTYPE run=\(i) typed ms=\(msOf(t0.duration(to: .now)))")
                try? await Task.sleep(for: .milliseconds(2000))
                input = ""
                pendingImages = []
                try? await Task.sleep(for: .milliseconds(1500))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowLog.info("camtypetest all done")
            return
        }
        if name == "camtrans" {
            UIApplication.shared.isIdleTimerDisabled = true
            guard let conv = store.conversations.first(where: { $0.messages.count > 20 }) else {
                flowLog.error("TEST no heavy conv")
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            store.currentID = conv.id
            try? await Task.sleep(for: .milliseconds(1500))
            guard let shot = await flowTestPicture() else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            for round in 1...6 {
                let duringDismissal = round <= 3
                flowMark("CAMTRANS run=\(round) during=\(duringDismissal) present")
                inputFocused = true
                try? await Task.sleep(for: .milliseconds(1200))
                CameraPresenter.shared.present()
                try? await Task.sleep(for: .milliseconds(3500))
                CameraPresenter.shared.dismissPresented()
                if duringDismissal {
                    pendingImages = [(image: shot, file: nil)]
                } else {
                    try? await Task.sleep(for: .milliseconds(1200))
                    pendingImages = [(image: shot, file: nil)]
                }
                try? await Task.sleep(for: .milliseconds(4000))
                flowMark("CAMTRANS run=\(round) attached pending=\(pendingImages.count)")
                try? await Task.sleep(for: .milliseconds(3000))
                pendingImages = []
                try? await Task.sleep(for: .milliseconds(1500))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowMark("CAMTRANS all done")
            return
        }
        if name == "camflow" {
            UIApplication.shared.isIdleTimerDisabled = true
            guard let img = await flowTestPicture() else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            for i in 1...flowTestRounds {
                flowLog.info("CAMFLOW run=\(i) begin")
                store.newConversation()
                try? await Task.sleep(for: .milliseconds(600))
                inputFocused = true
                pendingImages = [(image: img, file: nil)]
                try? await Task.sleep(for: .milliseconds(1500))
                input = "Mache das Bild etwas heller \(i)"
                await send()
                flowLog.info("CAMFLOW run=\(i) send returned")
                try? await Task.sleep(for: .milliseconds(6000))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowLog.info("camflow all done")
            return
        }
        if name == "followup" {
            UIApplication.shared.isIdleTimerDisabled = true
            guard let conv = store.conversations.first(where: { c in
                c.messages.contains { m in (m.outImages ?? []).contains { $0.file == flowTestEditImage } }
            }) else { flowLog.error("TEST no edit conv"); UIApplication.shared.isIdleTimerDisabled = false; return }
            store.currentID = conv.id
            try? await Task.sleep(for: .milliseconds(1500))
            for i in 1...flowTestRounds {
                flowLog.info("FOLLOWUP run=\(i) begin")
                let t0 = ContinuousClock.now
                input = "Bitte realitätsnaher mit Bränden und Rauch, Durchlauf \(i)"
                await send()
                flowLog.info("FOLLOWUP run=\(i) send returned ms=\(msOf(t0.duration(to: .now)))")
                try? await Task.sleep(for: .milliseconds(3000))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowLog.info("followup all done")
            return
        }
        if name == "tripleedit" || name == "bigedit" {
            UIApplication.shared.isIdleTimerDisabled = true
            let marker = name == "bigedit" ? flowTestBigImage : flowTestEditImage
            guard let conv = store.conversations.first(where: { c in
                c.messages.contains { m in (m.outImages ?? []).contains { $0.file == marker } }
            }) else { flowLog.error("TEST no edit conv"); UIApplication.shared.isIdleTimerDisabled = false; return }
            store.currentID = conv.id
            flowLog.info("\(name, privacy: .public) conv msgs=\(conv.messages.count)")
            try? await Task.sleep(for: .milliseconds(1500))
            for i in 1...flowTestRounds {
                flowLog.info("TRIPLE run=\(i) begin")
                let pool = conv.messages.flatMap(\.pictures)
                guard let cand = pool.last(where: { a in store.media.data(for: a) != nil }) ?? pool.last else { flowLog.error("TRIPLE run=\(i) no candidate"); break }
                let t0 = ContinuousClock.now
                attachForEditing(cand)
                flowLog.info("TRIPLE run=\(i) attached ms=\(msOf(t0.duration(to: .now)))")
                try? await Task.sleep(for: .milliseconds(2500))
                input = "Mache das Bild etwas heller"
                await send()
                flowLog.info("TRIPLE run=\(i) send returned")
                try? await Task.sleep(for: .milliseconds(4000))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            flowLog.info("TRIPLE all done")
            return
        }
        if name == "reopenbig" || name == "editbig" {
            guard let conv = store.conversations.first(where: { c in
                c.messages.contains { m in (m.outImages ?? []).contains { $0.file == flowTestBigImage } }
            }) else { flowLog.error("TEST no big conv"); return }
            let target = store.conversations.first { $0.id != conv.id }?.id
            for i in 1...flowTestRounds {
                flowLog.info("REOPEN pass=\(i) begin")
                let t0 = ContinuousClock.now
                store.currentID = target
                try? await Task.sleep(for: .milliseconds(400))
                store.currentID = conv.id
                try? await Task.sleep(for: .milliseconds(2200))
                flowLog.info("REOPEN pass=\(i) done ms=\(msOf(t0.duration(to: .now)))")
            }
            if name == "editbig" {
                guard let big = all.first(where: { $0.file == flowTestBigImage }) else {
                    flowLog.error("EDITBIG no stored image")
                    return
                }
                flowLog.info("EDITBIG attach begin")
                attachForEditing(big)
                try? await Task.sleep(for: .milliseconds(800))
                input = "Mache das Bild etwas heller"
                await send()
                flowLog.info("EDITBIG send returned")
            }
            return
        }
        guard let att = all.first(where: { $0.file == name }) ?? all.first
            ?? lastImageCandidate() else { return }
        flowLog.info("TEST step1 attachForEditing file=\(name, privacy: .public)")
        attachForEditing(att)
        try? await Task.sleep(for: .milliseconds(800))
        guard !pendingImages.isEmpty else { flowLog.error("TEST no pending image"); return }
        flowLog.info("TEST step2 input+send")
        input = "Mache das Bild etwas heller"
        await send()
        flowLog.info("TEST step3 send returned")
    }
}
#endif
