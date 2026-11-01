@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

enum PictureProbe {
    static let report = "picture_sweep.txt"

    static let lighten = "Mache das Bild etwas heller"
    static let squareOntoCircle = "Übertrage die Farbe des blauen Quadrats auf den roten Kreis."
    static let starOntoCircle = "Nimm die Farbe des gelben Sterns und male den roten Kreis damit an."
    static let triangleFromCircle = "Gib dem grünen Dreieck die Farbe des roten Kreises."
    static let recolourAsks = [PictureProbe.squareOntoCircle, PictureProbe.triangleFromCircle]

    enum Kind {
        case ellipse, rectangle, triangle, star, roundedRectangle
    }

    struct Fixture {
        let file: String
        let shape: String
        let colour: String
        let canvas: CGSize
        let background: UIColor
        let object: UIColor
        let kind: Kind

        func image() -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
                background.setFill()
                context.fill(CGRect(origin: .zero, size: canvas))
                object.setFill()
                let path = UIBezierPath()
                switch kind {
                case .ellipse:
                    let box = inset(0.34)
                    path.append(UIBezierPath(roundedRect: box, cornerRadius: box.width / 2))
                case .rectangle:
                    path.append(UIBezierPath(rect: inset(0.28)))
                case .roundedRectangle:
                    path.append(UIBezierPath(roundedRect: inset(0.3), cornerRadius: canvas.width * 0.03))
                case .triangle:
                    let box = inset(0.22)
                    path.move(to: CGPoint(x: box.midX, y: box.minY))
                    path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
                    path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
                    path.close()
                case .star:
                    star(into: path)
                }
                path.fill()
            }
        }

        private func inset(_ ratio: CGFloat) -> CGRect {
            let side = min(canvas.width, canvas.height)
            let box = CGSize(width: side * (1 - ratio * 2), height: side * (1 - ratio * 2))
            return CGRect(x: (canvas.width - box.width) / 2, y: (canvas.height - box.height) / 2,
                          width: box.width, height: box.height)
        }

        private func star(into path: UIBezierPath) {
            let box = inset(0.18)
            let centre = CGPoint(x: box.midX, y: box.midY)
            let outer = min(box.width, box.height) / 2
            for point in 0..<10 {
                let radius = point.isMultiple(of: 2) ? outer : outer * 0.42
                let angle = -CGFloat.pi / 2 + CGFloat(point) * .pi / 5
                let at = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
                if point == 0 { path.move(to: at) } else { path.addLine(to: at) }
            }
            path.close()
        }

        func data() -> Data? {
            image().jpegData(compressionQuality: ImagePolicy.jpegQuality)
        }
    }

    struct TestCase {
        let name: String
        var attached: Fixture? = nil
        var extra: [Fixture] = []
        let instruction: String
        let shape: String
        let colours: [String]
        var expectsPicture = true
        var question = PictureProbe.shapeQuestion
    }

    static let circle = Fixture(file: "img_probe_kreis.jpg", shape: "kreis", colour: "rot",
                                canvas: CGSize(width: 900, height: 1400),
                                background: UIColor(white: 0.98, alpha: 1),
                                object: UIColor(red: 0.82, green: 0.13, blue: 0.15, alpha: 1),
                                kind: .ellipse)
    static let square = Fixture(file: "img_probe_quadrat.jpg", shape: "quadrat", colour: "blau",
                                canvas: CGSize(width: 1400, height: 900),
                                background: UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
                                object: UIColor(red: 0.12, green: 0.35, blue: 0.78, alpha: 1),
                                kind: .rectangle)
    static let triangle = Fixture(file: "img_probe_dreieck.jpg", shape: "dreieck", colour: "grun",
                                  canvas: CGSize(width: 1100, height: 1100),
                                  background: UIColor(red: 0.67, green: 0.84, blue: 0.98, alpha: 1),
                                  object: UIColor(red: 0.11, green: 0.59, blue: 0.28, alpha: 1),
                                  kind: .triangle)
    static let star = Fixture(file: "img_probe_stern.jpg", shape: "stern", colour: "gelb",
                              canvas: CGSize(width: 1000, height: 1300),
                              background: UIColor(red: 0.06, green: 0.25, blue: 0.17, alpha: 1),
                              object: UIColor(red: 0.94, green: 0.78, blue: 0.12, alpha: 1),
                              kind: .star)
    static let rectangle = Fixture(file: "img_probe_rechteck.jpg", shape: "rechteck", colour: "schwarz",
                                   canvas: CGSize(width: 1300, height: 800),
                                   background: UIColor(red: 0.98, green: 0.88, blue: 0.67, alpha: 1),
                                   object: UIColor(white: 0.1, alpha: 1),
                                   kind: .roundedRectangle)

    static let fixtures = [circle, square, triangle, star]
    static var all: [Fixture] { fixtures + [rectangle] }

    static func materialise(in media: MediaStore) {
        for fixture in all where media.data(named: fixture.file) == nil {
            if let data = fixture.data() {
                try? data.write(to: media.paths.image(fixture.file))
            }
        }
    }

    static let shapeQuestion = "Sage in genau einem Satz: Wie heißt die Hauptform, die du siehst – nenne ihr "
        + "Formwort –, und welche Farbe hat sie?"
    static let sizeQuestion = "Sage in genau einem Satz: Wie heißt die Hauptform, die du siehst – nenne ihr "
        + "Formwort –, welche Farbe hat sie, wie groß füllt sie das Bild (klein, mittel oder fast vollständig), "
        + "und wie viele verschiedene Hauptformen sind es insgesamt?"
    static let objectCountQuestion = "Antworte mit genau einem Wort (eins, zwei oder drei): Wie viele "
        + "verschiedene Hauptformen (Objekte) sind in diesem Bild zu sehen?"
    static let backgroundQuestion = "Sage in genau einem Satz: Wie heißt die Hauptform, die du siehst – nenne "
        + "ihr Formwort –, in welcher Farbe sie ist, und welche Farbe hat der Hintergrund?"

    static let cases: [TestCase] = [
        TestCase(name: "farbe_quadrat_auf_kreis",
                 instruction: PictureProbe.squareOntoCircle,
                 shape: "kreis", colours: ["blau"]),
        TestCase(name: "farbe_stern_auf_kreis",
                 instruction: PictureProbe.starOntoCircle,
                 shape: "kreis", colours: ["gelb"]),
        TestCase(name: "farbe_kreis_auf_dreieck",
                 instruction: PictureProbe.triangleFromCircle,
                 shape: "dreieck", colours: ["rot"]),
        TestCase(name: "frisch_mitgeschickt_auf_kreis", attached: square,
                 instruction: "Übertrage die Farbe von dem Foto, das ich dir gerade mitschicke, "
                 + "auf den roten Kreis im Chat.",
                 shape: "kreis", colours: ["blau"]),
        TestCase(name: "groesse_stern_wie_kreis",
                 instruction: "Mache den Gegenstand aus dem gelben Stern genau so groß wie den "
                 + "Gegenstand aus dem roten Kreis.",
                 shape: "stern", colours: ["gelb"], question: sizeQuestion),
        TestCase(name: "hintergrund_quadrat_auf_stern",
                 instruction: "Nimm den Hintergrund aus dem Quadrat und gib ihn dem gelben Stern.",
                 shape: "stern", colours: ["grau", "schwarz", "dunkel"], question: backgroundQuestion),
        TestCase(name: "nur_frage_kein_bild",
                 instruction: "Was ist auf dem roten Kreis zu sehen?",
                 shape: "kreis", colours: ["rot"], expectsPicture: false),
        TestCase(name: "ueberlauf_kappe_haelt_erstes_und_neueste", extra: [rectangle],
                 instruction: "Ändere die Farbe des roten Kreises in die Farbe des grünen Dreiecks.",
                 shape: "kreis", colours: ["grun"]),
    ]

    static func folded(_ text: String) -> String { CalendarChoice.normalize(text) }

    static let hueWords: [String: [String]] = [
        "gelb": ["gold", "bernstein", "ocker", "senf"],
        "blau": ["kobalt", "saphir", "marine", "ultramarin"],
        "rot": ["zinnober", "scharlach", "karmesin"],
        "grun": ["smaragd", "jade"],
        "grau": ["silber", "anthrazit"],
        "schwarz": ["dunkel"],
    ]

    static func matchesColour(_ colours: [String], in text: String) -> Bool {
        colours.flatMap { [$0] + (hueWords[$0] ?? []) }.contains { text.contains($0) }
    }

    static func foreignShapes(except shape: String) -> [String] {
        all.map(\.shape).filter { $0 != shape }
    }

    static func meanRGB(of image: UIImage) -> (Int, Int, Int) {
        let side = 24
        guard let pixels = PixelBuffer.rgba(of: image, side: side) else { return (0, 0, 0) }
        var red = 0, green = 0, blue = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[offset])
            green += Int(pixels[offset + 1])
            blue += Int(pixels[offset + 2])
        }
        let count = side * side
        return (red / count, green / count, blue / count)
    }

    static func rgbText(_ image: UIImage) -> String {
        let rgb = meanRGB(of: image)
        return "\(Int(image.size.width))x\(Int(image.size.height)) rgb(\(rgb.0),\(rgb.1),\(rgb.2))"
    }
}
#endif
