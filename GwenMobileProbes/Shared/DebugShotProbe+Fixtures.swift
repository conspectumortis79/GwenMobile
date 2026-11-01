@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugShotProbe {
    static func documentPage(title: String, text: String) -> UIImage {
        let size = CGSize(width: 595, height: 842)
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor(white: 0.15, alpha: 1),
                .paragraphStyle: paragraph
            ]
            title.draw(at: CGPoint(x: 56, y: 70), withAttributes: titleAttributes)
            let body = text.components(separatedBy: "\n").filter { !$0.isEmpty }.joined(separator: "\n")
            body.draw(in: CGRect(x: 56, y: 120, width: 483, height: 640), withAttributes: bodyAttributes)
        }
    }

    static func fillGradient(_ c: CGContext, _ colors: [UIColor], _ rect: CGRect) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors.map(\.cgColor) as CFArray, locations: nil)
        else { return }
        c.saveGState()
        c.clip(to: rect)
        c.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                             end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        c.restoreGState()
    }

    static func scatterStars(_ c: CGContext, count: Int, in rect: CGRect, seed: UInt64) {
        var value = seed
        c.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
        for _ in 0..<count {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let x = rect.minX + CGFloat(value % UInt64(max(1, Int(rect.width))))
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let y = rect.minY + CGFloat(value % UInt64(max(1, Int(rect.height))))
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let radius = 1 + CGFloat(value % 2)
            c.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
    }

    static func nightLighthouse() -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            fillGradient(c, [UIColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1),
                             UIColor(red: 0.16, green: 0.20, blue: 0.42, alpha: 1)],
                         CGRect(x: 0, y: 0, width: 800, height: 660))
            scatterStars(c, count: 80, in: CGRect(x: 0, y: 0, width: 800, height: 540), seed: 7)
            UIColor(red: 0.03, green: 0.09, blue: 0.20, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 640, width: 800, height: 360))
            UIColor(red: 1, green: 0.93, blue: 0.55, alpha: 0.16).setFill()
            for direction in [CGFloat(-1), 1] {
                let beam = UIBezierPath()
                beam.move(to: CGPoint(x: 400, y: 300))
                beam.addLine(to: CGPoint(x: 400 + direction * 340, y: 170))
                beam.addLine(to: CGPoint(x: 400 + direction * 340, y: 430))
                beam.close()
                beam.fill()
            }
            let tower = UIBezierPath()
            tower.move(to: CGPoint(x: 356, y: 640))
            tower.addLine(to: CGPoint(x: 444, y: 640))
            tower.addLine(to: CGPoint(x: 420, y: 318))
            tower.addLine(to: CGPoint(x: 380, y: 318))
            tower.close()
            c.saveGState()
            tower.addClip()
            UIColor(white: 0.93, alpha: 1).setFill()
            tower.fill()
            UIColor(red: 0.82, green: 0.20, blue: 0.20, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 340, y: 420, width: 120, height: 52)).fill()
            UIBezierPath(rect: CGRect(x: 340, y: 540, width: 120, height: 48)).fill()
            c.restoreGState()
            UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 382, y: 288, width: 36, height: 30)).fill()
            UIColor(white: 0.15, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 374, y: 282, width: 52, height: 8)).fill()
            fillGradient(c, [UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.22),
                             UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 0)],
                         CGRect(x: 340, y: 640, width: 120, height: 260))
        }
    }

    static func mountainLake(gray: Bool) -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            let sky: [UIColor] = gray
                ? [UIColor(white: 0.72, alpha: 1), UIColor(white: 0.92, alpha: 1)]
                : [UIColor(red: 0.32, green: 0.60, blue: 0.90, alpha: 1),
                   UIColor(red: 0.85, green: 0.93, blue: 0.99, alpha: 1)]
            fillGradient(c, sky, CGRect(x: 0, y: 0, width: 800, height: 620))
            let sun: UIColor = gray ? UIColor(white: 0.98, alpha: 1)
                                    : UIColor(red: 1, green: 0.92, blue: 0.62, alpha: 1)
            sun.setFill()
            c.fillEllipse(in: CGRect(x: 610, y: 90, width: 110, height: 110))
            let far: UIColor = gray ? UIColor(white: 0.45, alpha: 1)
                                    : UIColor(red: 0.35, green: 0.45, blue: 0.55, alpha: 1)
            far.setFill()
            let range = UIBezierPath()
            range.move(to: CGPoint(x: 0, y: 620))
            range.addLine(to: CGPoint(x: 190, y: 380))
            range.addLine(to: CGPoint(x: 330, y: 560))
            range.addLine(to: CGPoint(x: 470, y: 330))
            range.addLine(to: CGPoint(x: 620, y: 560))
            range.addLine(to: CGPoint(x: 800, y: 420))
            range.addLine(to: CGPoint(x: 800, y: 620))
            range.close()
            range.fill()
            let near: UIColor = gray ? UIColor(white: 0.30, alpha: 1)
                                     : UIColor(red: 0.20, green: 0.40, blue: 0.28, alpha: 1)
            near.setFill()
            let hill = UIBezierPath()
            hill.move(to: CGPoint(x: 0, y: 620))
            hill.addLine(to: CGPoint(x: 240, y: 480))
            hill.addLine(to: CGPoint(x: 520, y: 620))
            hill.close()
            hill.fill()
            let water: UIColor = gray ? UIColor(white: 0.62, alpha: 1)
                                      : UIColor(red: 0.28, green: 0.62, blue: 0.78, alpha: 1)
            water.setFill()
            c.fill(CGRect(x: 0, y: 620, width: 800, height: 380))
            UIColor(white: 1, alpha: gray ? 0.25 : 0.35).setFill()
            c.fill(CGRect(x: 0, y: 620, width: 800, height: 10))
        }
    }

    static func aurora(_ variant: Int) -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        let palette: [(CGFloat, CGFloat, CGFloat)] = [(0.20, 0.90, 0.55), (0.30, 0.70, 0.95),
                                                      (0.65, 0.40, 0.95)]
        let base = palette[variant % palette.count]
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            fillGradient(c, [UIColor(red: 0.02, green: 0.03, blue: 0.10, alpha: 1),
                             UIColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 1)],
                         CGRect(x: 0, y: 0, width: 800, height: 740))
            scatterStars(c, count: 110, in: CGRect(x: 0, y: 0, width: 800, height: 620),
                         seed: UInt64(11 + variant))
            for band in 0..<3 {
                let path = UIBezierPath()
                let lift = CGFloat(band) * 60
                path.move(to: CGPoint(x: 0, y: 220 + lift))
                for step in stride(from: 0, through: 8, by: 1) {
                    let x = CGFloat(step) * 100
                    let y = 220 + lift + CGFloat((step % 3) * 26 - 26)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: 800, y: 380 + lift))
                path.addLine(to: CGPoint(x: 0, y: 380 + lift))
                path.close()
                UIColor(red: base.0, green: base.1, blue: base.2,
                        alpha: band == 0 ? 0.40 : 0.22).setFill()
                path.fill()
            }
            UIColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 1).setFill()
            let snow = UIBezierPath()
            snow.move(to: CGPoint(x: 0, y: 740))
            snow.addLine(to: CGPoint(x: 220, y: 680))
            snow.addLine(to: CGPoint(x: 520, y: 750))
            snow.addLine(to: CGPoint(x: 800, y: 690))
            snow.addLine(to: CGPoint(x: 800, y: 1000))
            snow.addLine(to: CGPoint(x: 0, y: 1000))
            snow.close()
            snow.fill()
        }
    }

    static func eiffelTower(_ variant: Int) -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        let skies: [[UIColor]] = [
            [UIColor(red: 0.98, green: 0.72, blue: 0.55, alpha: 1),
             UIColor(red: 0.55, green: 0.70, blue: 0.92, alpha: 1)],
            [UIColor(red: 0.45, green: 0.72, blue: 0.95, alpha: 1),
             UIColor(red: 0.88, green: 0.95, blue: 1.00, alpha: 1)],
            [UIColor(red: 0.45, green: 0.35, blue: 0.65, alpha: 1),
             UIColor(red: 0.95, green: 0.62, blue: 0.55, alpha: 1)],
            [UIColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1),
             UIColor(red: 0.16, green: 0.20, blue: 0.40, alpha: 1)]
        ]
        let sky = skies[variant % skies.count]
        let night = variant % skies.count == 3
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            fillGradient(c, sky, CGRect(x: 0, y: 0, width: 800, height: 1000))
            if night { scatterStars(c, count: 90, in: CGRect(x: 0, y: 0, width: 800, height: 700),
                                    seed: UInt64(31 + variant)) }
            UIColor(white: night ? 0.75 : 0.35, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 900, width: 800, height: 100))
            let iron: UIColor = night ? UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1)
                                      : UIColor(white: 0.12, alpha: 1)
            iron.setStroke()
            iron.setFill()
            for direction in [CGFloat(-1), 1] {
                let leg = UIBezierPath()
                leg.move(to: CGPoint(x: 400 + direction * 90, y: 900))
                leg.addQuadCurve(to: CGPoint(x: 400 + direction * 20, y: 430),
                                 controlPoint: CGPoint(x: 400 + direction * 80, y: 620))
                leg.lineWidth = 18
                leg.stroke()
            }
            for (index, width) in [200.0, 140.0, 80.0].enumerated() {
                let y = 560.0 + Double(index) * -95.0
                UIBezierPath(roundedRect: CGRect(x: 400 - width / 2, y: y, width: width, height: 16),
                             cornerRadius: 5).fill()
            }
            let spire = UIBezierPath()
            spire.move(to: CGPoint(x: 400, y: 400))
            spire.addLine(to: CGPoint(x: 400, y: 250))
            spire.lineWidth = 10
            spire.stroke()
            c.fillEllipse(in: CGRect(x: 393, y: 240, width: 14, height: 14))
        }
    }

    static func scanFixture(_ view: ChatView, kind: ScanKind, text: String) -> ScanOutcome? {
        let workflow = ScanWorkflow(recognize: { _, _ in text })
        let page = ReceiptCard.receiptCard(fontSize: 34, text: text)
        return workflow.store(pages: [page], kind: kind, date: day(0, hour: 20),
                              documents: view.store.documents)
    }

    static func day(_ offset: Int, hour: Int) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    static func germanDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    static func englishDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    static var cleanup: (@MainActor () async -> Void)?

    static func start(_ view: ChatView, file: String, name: String) -> UUID? {
        let report = SweepReport(file: file)
        let settings = AppSettings.shared
        let baseline = ShotBaseline(settings)
        view.voice.cancel()
        view.store.newConversation()
        guard let id = view.store.currentID else { return nil }
        cleanup = {
            view.showSettings = false
            view.showHistory = false
            view.showHelp = false
            view.attachMenu = false
            view.voice.cancel()
            baseline.restore(settings)
            _ = view.store.removeConversation(id)
            await view.store.flushPendingSave()
            cleanup = nil
        }
        report.add("SHOT", name)
        return id
    }

    static func focus(_ view: ChatView, on id: UUID) async {
        try? await Task.sleep(for: .milliseconds(1500))
        view.scrollProxy?.scrollTo(ChatScrollAnchors.message(id), anchor: .top)
        try? await Task.sleep(for: .milliseconds(400))
        view.scrollProxy?.scrollTo(ChatScrollAnchors.message(id), anchor: .top)
    }

    static func shotForecastJSON(date: String) -> Data {
        ForecastFixture.json(date: date)
    }

    static func scrollSettings(offset: CGFloat) async -> Bool {
        guard let view = topPresentedController()?.view,
              let scroll = largestScroll(in: view) else { return false }
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        try? await Task.sleep(for: .milliseconds(400))
        return true
    }

    private static func topPresentedController() -> UIViewController? {
        var controller = Presenter.windowRootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private static func largestScroll(in view: UIView) -> UIScrollView? {
        var found: UIScrollView?
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
            found = scroll
        }
        for sub in view.subviews {
            guard let candidate = largestScroll(in: sub) else { continue }
            if let current = found {
                if candidate.contentSize.height > current.contentSize.height { found = candidate }
            } else {
                found = candidate
            }
        }
        return found
    }

    static func hold() async {
        let marker = StoragePaths().documents.appendingPathComponent(DebugShotProbe.releaseMarkerName)
        DebugReleaseFlag.shot.consume()
        try? FileManager.default.removeItem(at: marker)
        flowMark("SHOT bereit")
        _ = await ProbeWait.until(120) {
            DebugReleaseFlag.shot.isRequested || FileManager.default.fileExists(atPath: marker.path)
        }
        DebugReleaseFlag.shot.consume()
        try? FileManager.default.removeItem(at: marker)
        await cleanup?()
        flowMark("SHOT freigegeben")
    }
}

@MainActor
final class DebugReleaseFlag {
    static let shot = DebugReleaseFlag()
    static let listen = DebugReleaseFlag()

    private var requested = false

    var isRequested: Bool { requested }

    func request() { requested = true }

    func consume() { requested = false }
}

@MainActor
struct ShotBaseline {
    private let voice: VoiceSettings
    private let appearance: AppAppearance
    private let language: AppLanguage

    init(_ settings: AppSettings, language target: AppLanguage = .en) {
        voice = settings.voice
        appearance = settings.appearance
        language = settings.language
        settings.appearance = .light
        settings.language = target
        settings.voice.listenMode = false
        settings.voice.conversationMode = false
    }

    func restore(_ settings: AppSettings) {
        settings.language = language
        settings.appearance = appearance
        settings.voice = voice
    }
}
#endif
