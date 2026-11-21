import Foundation
import GwenMobileKit

enum ToolSchemaNames {
    static func of(_ tools: [[String: Any]]) -> [String] {
        tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
    }
}
