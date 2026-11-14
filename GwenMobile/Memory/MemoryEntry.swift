import GwenMobileKit
import Foundation

enum MemoryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case person
    case likes
    case people
    case work
    case health
    case plans

    var id: String { rawValue }

    var labelKey: String { "memory_cat_" + rawValue }

    var promptName: String {
        switch self {
        case .person: return "about the user"
        case .likes: return "preference"
        case .people: return "person in the user's life"
        case .work: return "work"
        case .health: return "health"
        case .plans: return "everyday life or plan"
        }
    }

    var symbol: String {
        switch self {
        case .person: return "person.crop.circle"
        case .likes: return "heart"
        case .people: return "person.2"
        case .work: return "briefcase"
        case .health: return "cross.case"
        case .plans: return "calendar"
        }
    }

    var isSensitive: Bool { self == .health }

    static let fallback: MemoryCategory = .person
}

enum MemorySource: String, Codable, Sendable {
    case said
    case explicit
    case suggestion
    case manual

    var labelKey: String { "memory_source_" + rawValue }
}

enum MemoryRetention: String, CaseIterable, Identifiable, Codable, Sendable {
    case forever
    case twelveMonths
    case threeMonths

    var id: String { rawValue }
    var labelKey: String { "memory_retention_" + rawValue }

    var months: Int? {
        switch self {
        case .forever: return nil
        case .twelveMonths: return 12
        case .threeMonths: return 3
        }
    }
}

struct MemoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var text: String
    var category: MemoryCategory
    var source: MemorySource
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var pinned: Bool
    var sensitive: Bool
    var anchor: Date?
    var intervalMonths: Int?
    var dueDate: Date?
    var remind: Bool
    var notified: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, category, source, createdAt, updatedAt, lastUsedAt, useCount, pinned, sensitive,
             anchor, intervalMonths, dueDate, remind, notified
    }

    init(text: String, category: MemoryCategory, source: MemorySource = .said,
         createdAt: Date = Date(), updatedAt: Date = Date(), lastUsedAt: Date? = nil, useCount: Int = 0,
         pinned: Bool = false, sensitive: Bool? = nil, anchor: Date? = nil, intervalMonths: Int? = nil,
         dueDate: Date? = nil, remind: Bool = false, notified: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.category = category
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.pinned = pinned
        self.sensitive = sensitive ?? category.isSensitive
        self.anchor = anchor
        self.intervalMonths = intervalMonths
        self.dueDate = dueDate
        self.remind = remind
        self.notified = notified
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.metadata(UUID.self, .id, fallback: UUID())
        text = fields.content(String.self, .text, fallback: "")
        category = fields.metadata(MemoryCategory.self, .category, fallback: .person)
        source = fields.metadata(MemorySource.self, .source, fallback: .said)
        createdAt = fields.metadata(Date.self, .createdAt, fallback: Date())
        updatedAt = fields.metadata(Date.self, .updatedAt, fallback: createdAt)
        lastUsedAt = fields.metadata(Date.self, .lastUsedAt)
        useCount = max(0, fields.metadata(Int.self, .useCount, fallback: 0))
        pinned = fields.metadata(Bool.self, .pinned, fallback: false)
        sensitive = fields.metadata(Bool.self, .sensitive, fallback: category.isSensitive)
        anchor = fields.metadata(Date.self, .anchor)
        dueDate = fields.metadata(Date.self, .dueDate)
        intervalMonths = fields.metadata(Int.self, .intervalMonths)
            ?? Self.months(from: anchor, to: dueDate)
        remind = fields.metadata(Bool.self, .remind, fallback: false)
        notified = fields.metadata(Bool.self, .notified, fallback: false)
    }

    var shortKey: String { EntityKey.short(id) }

    static let averageMonthDays = 365.2425 / 12

    static func months(from anchor: Date?, to due: Date?) -> Int? {
        guard let anchor, let due,
              let days = Calendar.current.dateComponents([.day], from: anchor, to: due).day else { return nil }
        return Int((Double(days) / averageMonthDays).rounded())
    }
}

struct MemoryRef: Codable, Hashable, Sendable {
    var text: String
    var category: MemoryCategory

    init(entry: MemoryEntry) {
        self.text = entry.text
        self.category = entry.category
    }
}

struct MemorySuggestion: Codable, Hashable, Sendable {
    var text: String
    var category: MemoryCategory
    var anchor: Date?
    var intervalMonths: Int?
    var replaceKey: String?
}

struct MemoryRequest: Equatable, Sendable {
    enum Action: String, Equatable, Sendable {
        case create
        case suggest
        case forget
        case list
    }

    var action: Action
    var text: String? = nil
    var category: MemoryCategory? = nil
    var date: Date? = nil
    var intervalMonths: Int? = nil
    var key: String? = nil
    var replaceKey: String? = nil
}
