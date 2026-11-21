import GwenMobileKit
import Foundation

enum CatalogLine {
    static func entry(key: String, text: String, limit: Int, notes: [String]) -> String {
        "[#" + key + "] " + TextLine.oneLine(text, limit: limit) + " (" + notes.joined(separator: ", ") + ")"
    }
}
