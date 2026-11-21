@testable import GwenMobileFeatureCore
import Foundation

extension ConversationLoad {
    var conversations: [Conversation]? {
        switch self {
        case .loaded(let stored), .recovered(let stored, _): return stored
        case .nothing, .quarantined: return nil
        }
    }
}
