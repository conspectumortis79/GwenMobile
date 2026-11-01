@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

struct WeatherCard: View, Equatable {
    let ref: WeatherRef
    var onDay: ((String) -> Void)? = nil
    var onSpeak: (() -> Void)? = nil
    var showsActions = true
    #if DEBUG
    var probeHour: Binding<Int?>? = nil
    var probeHourValue: Int? = nil
    var probeSelectedHour: ((Int) -> Void)? = nil
    #endif
    @State private var hour: Int?
    @ScaledMetric var graphLabelSize: CGFloat = 10

    nonisolated static func == (lhs: WeatherCard, rhs: WeatherCard) -> Bool {
        #if DEBUG
        return lhs.ref == rhs.ref && lhs.showsActions == rhs.showsActions
            && lhs.probeHourValue == rhs.probeHourValue
        #else
        return lhs.ref == rhs.ref && lhs.showsActions == rhs.showsActions
        #endif
    }

    private var advice: [WeatherAdvice] { WeatherAdviceRules.advice(for: ref) }

    private var hourState: Binding<Int?> {
        #if DEBUG
        if let probeHour { return probeHour }
        #endif
        return $hour
    }

    private var selectedHour: Int {
        if let value = hourState.wrappedValue { return value }
        return ref.hours.first(where: { $0.hour == 14 })?.hour ?? ref.hours.first?.hour ?? 12
    }

    private var temps: [Double] { ref.hours.map(\.temp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showsActions {
                DayTabPicker(tabs: dayTabs.map { DayTabPicker.Tab(id: $0, title: WeatherAnswers.dayTitle($0)) },
                             selected: ref.day,
                             onSelect: { onDay?($0) })
            }
            banner
            WeatherHourScrubber(ref: ref, selectedHour: selectedHour, labelSize: graphLabelSize) {
                hourState.wrappedValue = $0
            }
            readout
            WeatherTilesView(ref: ref)
            WeatherIconRow(ref: ref)
            footer
        }
        .cardChrome()
        #if DEBUG
        .onChange(of: selectedHour, initial: true) { _, value in probeSelectedHour?(value) }
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .scaledFont(12, weight: .semibold)
                    Text(ref.place)
                        .scaledFont(16, weight: .bold)
                        .lineLimit(1)
                }
                Text(WeatherAnswers.dayTitle(ref.day) + " · " + WeatherAdviceRules.summary(for: ref))
                    .scaledFont(12.5)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                Image(systemName: middleKind.symbol)
                    .scaledFont(30)
                    .symbolRenderingMode(.multicolor)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rangeText)
                        .scaledFont(13, weight: .semibold)
                    Text("\(WeatherAdviceRules.number(temps.max() ?? 0))°")
                        .scaledFont(11)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
        }
    }

    private var middleKind: WeatherKind {
        guard !ref.hours.isEmpty else { return .cloud }
        return ref.hours[ref.hours.count / 2].kind
    }

    private var rangeText: String {
        "\(WeatherAdviceRules.number(temps.min() ?? 0))–\(WeatherAdviceRules.number(temps.max() ?? 0)) °C"
    }

    private var dayTabs: [String] {
        WeatherDayTabs.dates(selected: ref.day)
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(advice.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.symbol)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(item.level.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .scaledFont(13.5, weight: .bold)
                        Text(item.detail)
                            .scaledFont(13)
                            .foregroundStyle(Color(.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11)
            .fill((advice.first?.level.color ?? .gray).opacity(0.14)))
    }

    private var readout: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Text(WeatherAnswers.hourLine(ref, hour: selectedHour))
                .scaledFont(12.5)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(L.t("weather_attribution"))
                .scaledFont(10.5)
                .foregroundStyle(Color(.tertiaryLabel))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if showsActions {
                if let onSpeak {
                    footerButton("speaker.wave.2", label: L.t("read_aloud"), action: onSpeak)
                }
                footerButton("square.and.arrow.up", label: L.t("share"), action: export)
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(.separator).opacity(0.4)).frame(height: 0.5)
        }
    }

    private func footerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(13, weight: .semibold)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityLabel(Text(label))
    }

    @MainActor func export() {
        let renderer = ImageRenderer(content: WeatherCard(ref: ref, showsActions: false))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 300, height: nil)
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        let name = "wetter-" + Self.slug(ref.place) + "-" + ref.day + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url, options: [.atomic])) != nil else { return }
        try? Presenter.share(url: url)
    }

    nonisolated private static func slug(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
    }
}

extension WeatherAdvice.Level {
    var color: Color {
        switch self {
        case .green: return .green
        case .blue: return .blue
        case .orange: return .orange
        case .red: return .red
        }
    }
}
