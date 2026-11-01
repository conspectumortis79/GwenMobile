@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct PriceWatchView: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var settings = AppSettings.shared
    @State private var watches: [PriceWatch] = []
    @State private var checking: UUID?
    @State private var alert: String?
    @State private var undo: UndoItem?

    var body: some View {
        List {
            if watches.isEmpty {
                Text(L.t("price_watch_empty"))
                    .foregroundStyle(Color(.secondaryLabel))
            } else {
                Section {
                    ForEach(watches) { watch in
                        row(watch)
                    }
                } footer: {
                    Text(L.t("price_watch_settings_footer"))
                }
            }
        }
        .sheetToolbar(L.t("price_watch_view_title"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let undo {
                UndoToast(title: L.t("price_watch_undo_title"),
                          detail: undo.watch.product,
                          onUndo: { restore(undo.watch) },
                          onExpire: { if self.undo?.id == undo.id { self.undo = nil } })
                    .id(undo.id)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: undo?.id)
        .task { await reload() }
        .alert(L.t("price_watch_view_title"), isPresented: Binding(get: { alert != nil },
                                                                   set: { if !$0 { alert = nil } })) {
            Button(L.t("ok"), action: TapProbe.action({ alert = nil }))
        } message: {
            Text(alert ?? "")
        }
    }

    private struct UndoItem: Identifiable {
        let id = UUID()
        let watch: PriceWatch
    }

    private func row(_ watch: PriceWatch) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundStyle(watch.status.tint)
                .scaledFont(14, weight: .semibold)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: watch.product)
                    .scaledFont(15, weight: .semibold)
                Text(verbatim: Self.meta(watch))
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                if watch.isDue(now: Date()) {
                    Text(L.t("price_watch_due"))
                        .font(.caption)
                        .foregroundStyle(Color(.systemOrange))
                }
            }
            Spacer(minLength: 6)
            if checking == watch.id {
                ProgressView()
            } else {
                Button(action: TapProbe.action({
                    checkNow(watch)
                })) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.t("price_watch_check_now"))
                Toggle("", isOn: Binding(
                    get: { !watch.paused },
                    set: { wanted in setPaused(watch, paused: !wanted) }
                ))
                .labelsHidden()
                .accessibilityLabel(watch.paused ? L.t("price_watch_resume") : L.t("price_watch_pause"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: TapProbe.action({ openOffer(watch) }))
        .contextMenu { menu(watch) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: TapProbe.action({
                delete(watch)
            })) {
                Label(L.t("price_watch_delete"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func menu(_ watch: PriceWatch) -> some View {
        Button(action: TapProbe.action({ checkNow(watch) })) {
            Label(L.t("price_watch_check_now"), systemImage: "arrow.clockwise")
        }
        if let raw = watch.lastURL, !raw.isEmpty, URL(string: raw) != nil {
            Button(action: TapProbe.action({ openOffer(watch) })) {
                Label(L.t("price_watch_open_offer"), systemImage: "arrow.up.forward.app")
            }
        }
        Button(action: TapProbe.action({ setPaused(watch, paused: !watch.paused) })) {
            Label(watch.paused ? L.t("price_watch_resume") : L.t("price_watch_pause"),
                  systemImage: watch.paused ? "play.fill" : "pause.fill")
        }
        Divider()
        Button(role: .destructive, action: TapProbe.action({ delete(watch) })) {
            Label(L.t("price_watch_delete"), systemImage: "trash")
        }
    }

    static func meta(_ watch: PriceWatch) -> String {
        var parts = [L.fmt("price_watch_list_goal", Formatters.price(watch.goal,
                                                                    currency: watch.currencyCode)),
                     L.t("price_watch_status_" + watch.status.rawValue),
                     L.n("price_watch_interval_hours", watch.intervalHours)]
        if let price = watch.lastPrice {
            let seen = Formatters.price(price, currency: watch.lastCurrency ?? watch.currencyCode)
            if let shop = watch.lastShop, !shop.isEmpty {
                parts.append(L.fmt2("price_watch_list_seen_at", seen, shop))
            } else {
                parts.append(L.fmt("price_watch_list_seen", seen))
            }
        }
        if let checked = watch.lastCheckedAt {
            parts.append(L.fmt("price_watch_checked_at", Formatters.eventChip(checked)))
        } else {
            parts.append(L.t("price_watch_never_checked"))
        }
        return parts.joined(separator: " · ")
    }

    static func makeRunner(store: ChatStore, settings: AppSettings) -> PriceWatchFlowRunner {
        PriceWatchFlowRunner(store: store.watches,
                             checker: LivePriceWatchChecker(lookup: WebPriceLookup { _ in }),
                             credentials: PriceWatchCredentials(settings: settings),
                             notifier: LocalPriceWatchNotifier())
    }

    private func reload() async {
        watches = await store.watches.all()
    }

    static func setPaused(_ watch: PriceWatch, paused: Bool, store: ChatStore) async {
        await store.watches.setPaused(id: watch.id, paused: paused)
    }

    @discardableResult
    static func delete(_ watch: PriceWatch, store: ChatStore) async -> PriceWatch? {
        await store.watches.delete(key: watch.shortKey, terms: [])
    }

    private func setPaused(_ watch: PriceWatch, paused: Bool) {
        Task {
            await Self.setPaused(watch, paused: paused, store: store)
            await reload()
        }
    }

    private func delete(_ watch: PriceWatch) {
        Task {
            guard let deleted = await Self.delete(watch, store: store) else { return }
            await PriceWatchBackground.scheduleNext(store: store.watches)
            await reload()
            undo = UndoItem(watch: deleted)
        }
    }

    private func restore(_ watch: PriceWatch) {
        undo = nil
        Task {
            await store.watches.restore(watch)
            await PriceWatchBackground.scheduleNext(store: store.watches)
            await reload()
        }
    }

    private func checkNow(_ watch: PriceWatch) {
        guard settings.isConfigured else {
            alert = L.t("price_watch_need_provider")
            return
        }
        guard checking == nil else { return }
        checking = watch.id
        Task {
            let runner = Self.makeRunner(store: store, settings: settings)
            let outcome = await runner.checkOne(id: watch.id)
            await PriceWatchBackground.scheduleNext(store: store.watches)
            checking = nil
            await reload()
            if let outcome { alert = PriceWatchAnswers.checked(outcome) }
        }
    }

    private func openOffer(_ watch: PriceWatch) {
        guard let raw = watch.lastURL, let url = URL(string: raw) else { return }
        UIApplication.shared.open(url) { opened in
            flowMarkPersonal("PREISWECKER angebot geoeffnet=\(opened) domain=\(url.host ?? "-")")
        }
    }
}
