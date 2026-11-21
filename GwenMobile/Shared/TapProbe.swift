import Foundation

@MainActor
enum TapProbe {
    #if DEBUG
    static var actions: [() -> Void] = []
    static var indexByKey: [String: Int] = [:]

    static func action(_ body: @escaping () -> Void,
                       file: String = #fileID, line: Int = #line) -> () -> Void {
        let key = "\(file):\(line)"
        if let index = indexByKey[key] {
            actions[index] = body
        } else {
            indexByKey[key] = actions.count
            actions.append(body)
        }
        return body
    }
    #else
    static func action(_ body: @escaping () -> Void) -> () -> Void { body }
    #endif
}
