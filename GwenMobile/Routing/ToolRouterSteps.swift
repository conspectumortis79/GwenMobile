import GwenMobileKit
import Foundation

struct RouterAsk: Sendable {
    var baseURL: String
    var key: String
    var model: String
    var text: String
    var context: SendContext
    var history: [ChatMessage]
    var picture: Data?
    var extraPictures: [Data] = []
    var allPictures: [Data] { extraPictures + (picture.map { [$0] } ?? []) }
    var catalog: String
    var eraseHistoryWord: String
    var document: String
    var thinking: ThinkingDirective
    var watchCatalog: String
    var compact: Bool
    var reminderLists: [String]
    var reminderPlaceExists: (@Sendable @MainActor (String) async -> Bool)?
    var videoGenerationAvailable = false

    init(baseURL: String, key: String, model: String, text: String, context: SendContext,
         history: [ChatMessage], picture: Data? = nil, extraPictures: [Data] = [], catalog: String = "",
         eraseHistoryWord: String = "", document: String = "", thinking: ThinkingDirective,
         watchCatalog: String = "", compact: Bool = false,
         reminderLists: [String] = [],
         reminderPlaceExists: (@Sendable @MainActor (String) async -> Bool)? = nil,
         videoGenerationAvailable: Bool = false) {
        self.baseURL = baseURL
        self.key = key
        self.model = model
        self.text = text
        self.context = context
        self.history = history
        self.picture = picture
        self.extraPictures = extraPictures
        self.catalog = catalog
        self.eraseHistoryWord = eraseHistoryWord
        self.document = document
        self.thinking = thinking
        self.watchCatalog = watchCatalog
        self.compact = compact
        self.reminderLists = reminderLists
        self.reminderPlaceExists = reminderPlaceExists
        self.videoGenerationAvailable = videoGenerationAvailable
    }
}

enum RouterHistory {
    static let compactLimit = 4

    static func forRouting(_ history: [ChatMessage], compact: Bool) -> [ChatMessage] {
        compact ? Array(history.suffix(compactLimit)) : history
    }
}

extension ToolRouter {
    #if DEBUG
    static func decide(_ ask: RouterAsk) async -> ToolDecision? {
        await steps(ask).first
    }
    #endif

    static func plan(_ ask: RouterAsk) async -> SendPlan {
        SendPlan.forming(await steps(ask))
    }

    static func steps(_ ask: RouterAsk) async -> [ToolDecision] {
        await RouterStepsPort.current.steps(ask)
    }

    static func scanReminder(baseURL: String, key: String, model: String, text: String,
                             context: SendContext, history: [ChatMessage], document: String,
                             catalog: String = "", eraseHistoryWord: String = "",
                             thinking: ThinkingDirective) async -> ToolDecision? {
        guard let request = try? scanReminderRequest(baseURL: baseURL, key: key, model: model, text: text,
                                                     context: context, history: history,
                                                     document: document, catalog: catalog,
                                                     eraseHistoryWord: eraseHistoryWord,
                                                     thinking: thinking) else { return nil }
        let decision = await plan(asking: { try await HTTP.jsonData(request) }).first
        guard case .reminder = decision?.route else { return nil }
        return decision
    }
}
