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
                        .font(.system(size: 11))
                        .textCase(nil)
                } footer: {
                    Text(L.t("fresh_start_note"))
                        .font(.system(size: 11))
                        .textCase(nil)
                }
            }
            .navigationTitle(L.t("history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.t("done")) { dismissAction() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("delete_all")) { confirmAll = true }
                        .foregroundStyle(Color.red)
                        .disabled(store.conversations.count < 1)
                }
            }
            .alert(L.t("delete_all_title"), isPresented: $confirmAll) {
                Button(L.t("delete_all"), role: .destructive) { cleaner.deleteAllConversations() }
                Button(L.t("cancel"), role: .cancel) {}
            } message: {
                Text(alertBody)
            }
            .task { await cleaner.refreshUsage() }
        }
    }

    private func row(_ conversation: Conversation) -> some View {
        Button {
            store.currentID = conversation.id
            dismissAction()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(subtitle(conversation))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(StorageUsage.bytesText(cleaner.usage.bytesByConversation[conversation.id] ?? 0))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(ago(conversation.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { cleaner.deleteConversation(conversation.id) } label: {
                Label(L.t("delete_conversation"), systemImage: "trash")
            }
        }
    }

    private var headerText: String {
        let usage = cleaner.usage
        return "\(usage.conversations) \(L.t("conversations_word")) · \(usage.imageBytesText)"
    }

    private var alertBody: String {
        let usage = cleaner.usage
        let images = "\(usage.imageFiles) \(L.t("images_word")) (\(usage.imageBytesText))"
        return L.fmt2("delete_all_body", String(usage.conversations), images)
    }

    private func subtitle(_ conversation: Conversation) -> String {
        let images = conversation.messages.reduce(0) { $0 + $1.images.count + ($1.outImages ?? []).count }
        return "\(Self.dayText(conversation.updatedAt)) · \(conversation.messages.count) \(L.t("messages_word")) · \(images) \(L.t("images_word"))"
    }

    private func ago(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L.t("today") }
        if cal.isDateInYesterday(date) { return L.t("yesterday") }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
