@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

@MainActor
final class BusyOverlay: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var label = ""

    private struct Entry {
        let id: UUID
        let label: String
    }

    private var entries: [Entry] = []

    func running<T>(_ label: String, _ work: @MainActor () async throws -> T) async rethrows -> T {
        let id = UUID()
        begin(label, id: id)
        defer { end(id) }
        return try await work()
    }

    static func pictureLabel(editing: Bool) -> String {
        editing ? L.t("editing_image") : L.t("generating_image")
    }

    private func begin(_ label: String, id: UUID) {
        entries.append(Entry(id: id, label: label))
        self.label = label
        isBusy = true
    }

    private func end(_ id: UUID) {
        entries.removeAll { $0.id == id }
        label = entries.last?.label ?? ""
        isBusy = !entries.isEmpty
    }
}
