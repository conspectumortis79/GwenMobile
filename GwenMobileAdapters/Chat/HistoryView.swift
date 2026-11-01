@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct HistoryView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var cleaner: HistoryCleaner
    @Environment(\.dismiss) private var dismissAction
    @State private var confirmAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.conversations) { conversation in
                        row(conversation)
                    }
                } header: {
                    Text(headerText)
                        .scaledFont(11)
                        .textCase(nil)
                } footer: {
                    Text(L.t("fresh_start_note"))
                        .scaledFont(11)
                        .textCase(nil)
                }
            }
            .navigationTitle(L.t("history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.t("done"), action: TapProbe.action({ dismissAction() }))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("delete_all"), action: TapProbe.action({ confirmAll = true }))
                        .foregroundStyle(Color.red)
                }
            }
            .deleteAllConfirmation(cleaner: cleaner, isPresented: $confirmAll)
            .task { await cleaner.refreshUsage() }
        }
        .windowAppearance()
    }

    private func row(_ conversation: Conversation) -> some View {
        Button(action: TapProbe.action({
            store.currentID = conversation.id
            dismissAction()
        })) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .scaledFont(15)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(subtitle(conversation))
                        .scaledFont(11)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(StorageUsage.bytesText(cleaner.usage.bytesByConversation[conversation.id] ?? 0))
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Color.primary)
                    Text(ago(conversation.updatedAt))
                        .scaledFont(11)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: TapProbe.action({ cleaner.deleteConversation(conversation.id) })) {
                Label(L.t("delete_conversation"), systemImage: "trash")
            }
        }
    }

    private var headerText: String { cleaner.usage.headerLine }

    static func imageCount(_ conversation: Conversation) -> Int {
        Set(conversation.messages.flatMap(\.storedImageFiles)).count
    }

    private func subtitle(_ conversation: Conversation) -> String {
        StorageUsage.joined([Formatters.relationalDay(conversation.updatedAt),
                             StorageUsage.counted(conversation.messages.count, "messages_word"),
                             StorageUsage.counted(Self.imageCount(conversation), "images_word")])
    }

    private func ago(_ date: Date) -> String { Formatters.time(date) }
}
