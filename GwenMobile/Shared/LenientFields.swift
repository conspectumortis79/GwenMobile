import GwenMobileKit
import Foundation

struct LenientFields<Key: CodingKey> {
    private let container: KeyedDecodingContainer<Key>
    private let issues: DecodeIssues?

    init(_ decoder: Decoder) throws {
        container = try decoder.container(keyedBy: Key.self)
        issues = decoder.decodeIssues
    }

    func content<Value: Decodable>(_ type: Value.Type, _ key: Key, fallback: Value) -> Value {
        read(type, key, reported: true) ?? fallback
    }

    func content<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        read(type, key, reported: true)
    }

    func metadata<Value: Decodable>(_ type: Value.Type, _ key: Key, fallback: Value) -> Value {
        read(type, key, reported: false) ?? fallback
    }

    func metadata<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        read(type, key, reported: false)
    }

    private func read<Value: Decodable>(_ type: Value.Type, _ key: Key, reported: Bool) -> Value? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch {
            if reported { issues?.noteDamaged(key.stringValue) }
            return nil
        }
    }
}
