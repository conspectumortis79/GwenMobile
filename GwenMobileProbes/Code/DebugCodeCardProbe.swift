@testable import GwenMobileSystem
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit

@MainActor
final class ProbeCodePresenter: CodeFilePresenting {
    var failure: Error?
    private(set) var urls: [URL] = []

    func present(url: URL) throws {
        if let failure { throw failure }
        urls.append(url)
    }
}

@MainActor
final class ProbeCodeExporter: CodeFileExporting {
    var failure: Error?
    private(set) var urls: [URL] = []

    func export(url: URL) throws {
        if let failure { throw failure }
        urls.append(url)
    }
}

@MainActor
final class ProbePasteboard: PasteboardWriting {
    private(set) var written: [String] = []

    func write(_ text: String) {
        written.append(text)
    }
}

@MainActor
enum DebugCodeCardProbe {
    private struct ProbeError: LocalizedError {
        var errorDescription: String? { "Probe-Fehler" }
    }

    static func run(_: ChatView) async {
        let started = ContinuousClock.now
        let report = SweepReport(file: "code_card.txt")
        let markdown = """
        Ein minimales Tetris in einer HTML-Datei:

        ```html
        <!doctype html>
        <html>
        <body>
        <canvas id="g" width="240" height="400"></canvas>
        <script>
        const c = g.getContext("2d");
        let board = Array.from({length: 20}, () => Array(10).fill(0));
        function draw() { c.fillStyle = "#111"; c.fillRect(0, 0, 240, 400); }
        onkeydown = event => { if (event.key === "ArrowLeft") x--; if (event.key === "ArrowRight") x++; };
        setInterval(() => { y++; draw(); }, 400);
        draw();
        </script>
        </body>
        </html>
        ```
        """
        guard let block = CodeText.blocks(in: markdown).first else {
            report.add("AUFBAU", "kein codeblock")
            return
        }
        let presenter = ProbeCodePresenter()
        let exporter = ProbeCodeExporter()
        let files = SavedCodeFiles()
        let actions = CodeCardActions(files: files, presenter: presenter, exporter: exporter)
        report.add("AUFBAU", "sprache=\(block.language.rawValue) zeilen=\(block.lineCount) "
                   + "browser=\(block.language.opensInBrowser)")

        var rendered = false
        let card = CodeBlockView(block: block, question: "Tetris", actions: actions,
                                 probeRendered: { rendered = true })
        if let window = ProbeHosting.host(card) {
            _ = await ProbeWait.until(3) { rendered }
            report.add("KARTE", "gerendert=\(rendered) screenshot="
                       + ProbeHosting.snapshot(window, "code_card.jpg"))
            ProbeHosting.close(window)
        } else {
            report.add("KARTE", "kein fenster")
        }

        if case .preview(let page) = actions.preview(block, question: "Tetris") {
            let data = (try? Data(contentsOf: page.url)) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            let lower = text.lowercased()
            let complete = lower.contains("<!doctype") && lower.contains("</html>")
            report.add("VORSCHAU", "datei=\(page.name) bytes=\(data.count) vollstaendig=\(complete) "
                       + "zaeune=\(text.contains(CodeText.fence))")
            report.add("VORSCHAU_CACHE", "gleiche_datei=\(actions.preview(block, question: "Tetris").pageURL == page.url)")
            cleanup(page.url)
        } else {
            report.add("VORSCHAU", "kein ergebnis")
        }

        _ = actions.share(block, question: "Tetris")
        if let url = presenter.urls.first, let data = try? Data(contentsOf: url) {
            report.add("TEILEN", "datei=\(url.lastPathComponent) bytes=\(data.count) aufrufe=\(presenter.urls.count)")
            cleanup(url)
        } else {
            report.add("TEILEN", "keine datei aufrufe=\(presenter.urls.count)")
        }

        _ = actions.download(block, question: "Tetris")
        if let url = exporter.urls.first, let data = try? Data(contentsOf: url) {
            report.add("HERUNTERLADEN", "datei=\(url.lastPathComponent) bytes=\(data.count) "
                       + "aufrufe=\(exporter.urls.count)")
            cleanup(url)
        } else {
            report.add("HERUNTERLADEN", "keine datei aufrufe=\(exporter.urls.count)")
        }

        let pasteboard = ProbePasteboard()
        let copy = AnswerCopyController(pasteboard: pasteboard)
        copy.perform(block.code)
        report.add("KOPIEREN", "bestaetigt=\(copy.confirmed) gleich=\(pasteboard.written == [block.code]) "
                   + "zeichen=\(pasteboard.written.first?.count ?? -1)")

        presenter.failure = ProbeError()
        let shareFailure = actions.share(block, question: "Tetris")
        report.add("TEILEN_FEHLER", "hinweis=\(isNotice(shareFailure))")
        presenter.failure = nil

        exporter.failure = ProbeError()
        let downloadFailure = actions.download(block, question: "Tetris")
        report.add("HERUNTERLADEN_FEHLER", "hinweis=\(isNotice(downloadFailure))")
        exporter.failure = nil

        report.add("DAUER", "ms=\(msOf(started.duration(to: .now)))")
        flowLog.info("CODECARD fertig")
    }

    private static func isNotice(_ outcome: CodeCardOutcome) -> Bool {
        if case .notice = outcome { return true }
        return false
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension CodeCardOutcome {
    var pageURL: URL? {
        if case .preview(let page) = self { return page.url }
        return nil
    }
}
#endif
