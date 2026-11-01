@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension ChatView {
    @MainActor func makeFixtures() async {
        let report = SweepReport(file: "fixtures_probe.txt")
        let paths = store.media.paths
        let big = PictureProbe.Fixture(file: flowTestBigImage, shape: "rechteck", colour: "blau",
                                      canvas: CGSize(width: 2400, height: 1600),
                                      background: UIColor(white: 0.93, alpha: 1),
                                      object: UIColor(red: 0.12, green: 0.28, blue: 0.86, alpha: 1),
                                      kind: .roundedRectangle)
        let edit = PictureProbe.Fixture(file: flowTestEditImage, shape: "kreis", colour: "rot",
                                       canvas: CGSize(width: 1536, height: 1536),
                                       background: UIColor(white: 0.12, alpha: 1),
                                       object: UIColor(red: 0.86, green: 0.18, blue: 0.16, alpha: 1),
                                       kind: .ellipse)
        for fixture in [big, edit] {
            let picture = fixture.image()
            if let data = picture.jpegData(compressionQuality: 0.92) {
                try? data.write(to: paths.image(fixture.file))
            }
            report.add("FIXTURE", "datei=\(fixture.file) bytes=\(store.media.byteSize(of: fixture.file)) "
                       + "form=\(fixture.shape) masse=\(Int(picture.size.width))x\(Int(picture.size.height))")
        }
        PictureProbe.materialise(in: store.media)
        for fixture in PictureProbe.all {
            report.add("FIXTURE", "datei=\(fixture.file) bytes=\(store.media.byteSize(of: fixture.file)) "
                       + "form=\(fixture.shape) masse=\(Int(fixture.canvas.width))x\(Int(fixture.canvas.height))")
        }

        store.newConversation()
        guard let conversation = store.current?.id else { return }
        for index in 0..<24 {
            var message = ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant,
                                      text: "Fixture-Nachricht \(index) — ein etwas längerer Satz, damit die Blase "
                                          + "echtes mehrzeiliges Layout, Quellennamen und Bilder hintereinander "
                                          + "durchläuft statt eines Kurztextes.")
            if index.isMultiple(of: 2) {
                message.outImages = [Attachment(file: index.isMultiple(of: 4) ? flowTestBigImage : flowTestEditImage)]
            }
            store.appendMessage(message, to: conversation)
        }
        await store.flushPendingSave()
        let holdsBig = store.conversations.contains { conversation in
            conversation.messages.contains { message in
                (message.outImages ?? []).contains { $0.file == flowTestBigImage }
            }
        }
        report.add("UNTERHALTUNG", "nachrichten=\(store.current?.messages.count ?? -1) "
                   + "bilder=\(store.current?.messages.reduce(0) { $0 + $1.pictures.count } ?? -1) "
                   + "dateien=\(store.media.fileNames().count) "
                   + "schwer=\(store.conversations.contains { $0.messages.count > 20}) "
                   + "bigKonversation=\(holdsBig)")
    }
}
#endif
