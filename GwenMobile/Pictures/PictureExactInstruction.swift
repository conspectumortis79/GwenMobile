import Foundation

enum PictureExactEdit: String, CaseIterable, Equatable, Sendable {
    case cropLeftHalf = "crop_left_half"
    case redDotCenter = "red_dot_center"

    static func list(from value: Any?) -> [PictureExactEdit] {
        let raw: [String]
        if let values = value as? [String] {
            raw = values
        } else if let single = value as? String {
            raw = [single]
        } else {
            raw = []
        }
        return raw.compactMap(PictureExactEdit.init(rawValue:))
    }
}

struct PictureExactInstruction: Equatable, Sendable {
    let exact: [PictureExactEdit]

    init(_ exact: [PictureExactEdit]) {
        self.exact = exact
    }

    var isEmpty: Bool { exact.isEmpty }

    var trace: String {
        exact.map(\.rawValue).joined(separator: "+")
    }

    func prompt(replacing fallback: String, blackAndWhite: Bool = false) -> String {
        guard !exact.isEmpty else { return fallback }
        var lines = ["Edit the provided image exactly as described. Do not rotate, crop or redraw anything that is not named here."]
        if exact.contains(.cropLeftHalf) {
            lines.append("Crop the image to its left half: keep exactly the left 50 % of the width and the full height, "
                + "remove everything from the vertical centre line to the right edge, add no black bars and no new "
                + "content. The output must be half as wide as the input.")
        }
        if exact.contains(.redDotCenter) {
            lines.append("Place one small solid red circular dot exactly in the centre of the image. Keep the whole "
                + "image, its orientation, colours, text and every other detail unchanged.")
        }
        if blackAndWhite {
            lines.append("The result is black and white.")
        }
        return lines.joined(separator: "\n")
    }
}
