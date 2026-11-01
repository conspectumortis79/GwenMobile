@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

struct WeatherCurveView: View {
    let ref: WeatherRef
    let selectedHour: Int
    let labelSize: CGFloat

    var body: some View {
        let temps = ref.hours.map(\.temp)
        let hours = ref.hours
        let selected = selectedHour
        return Canvas { context, size in
            guard temps.count > 1, let lo = temps.min(), let hi = temps.max() else { return }
            let span = max(hi - lo, 1)
            let top: CGFloat = 16
            let bottom = size.height - 10
            func point(_ index: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(temps.count - 1)
                let y = bottom - CGFloat((temps[index] - lo) / span) * (bottom - top)
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: point(0))
            for index in 1..<temps.count { line.addLine(to: point(index)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: bottom))
            area.addLine(to: CGPoint(x: 0, y: bottom))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            for index in temps.indices {
                let isSelected = hours[index].hour == selected
                let radius: CGFloat = isSelected ? 4.2 : 2.1
                let center = point(index)
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(isSelected ? .accentColor : Color(.systemBackground)))
                context.stroke(dot, with: .color(.accentColor), lineWidth: 1.6)
            }
            if let hiIndex = temps.firstIndex(of: hi) {
                context.draw(Text("\(WeatherAdviceRules.number(hi))°")
                    .font(.system(size: labelSize)).foregroundStyle(Color(.secondaryLabel)),
                             at: CGPoint(x: point(hiIndex).x, y: max(8, point(hiIndex).y - 9)))
            }
            if let loIndex = temps.firstIndex(of: lo) {
                context.draw(Text("\(WeatherAdviceRules.number(lo))°")
                    .font(.system(size: labelSize)).foregroundStyle(Color(.secondaryLabel)),
                             at: CGPoint(x: point(loIndex).x, y: min(size.height - 2, point(loIndex).y + 11)))
            }
        }
        .frame(height: 96)
    }
}

struct WeatherBarsView: View {
    let ref: WeatherRef
    let selectedHour: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(ref.hours, id: \.hour) { item in
                let isSelected = item.hour == selectedHour
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.barColor(item.rain))
                        .frame(height: max(3, CGFloat(item.rain) / 100 * 26))
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .frame(maxWidth: .infinity, maxHeight: 26, alignment: .bottom)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isSelected ? 0.14 : 0)))
            }
        }
        .frame(height: 26)
    }

    private static func barColor(_ rain: Int) -> Color {
        switch rain {
        case 65...: return .indigo
        case 40...: return .blue
        case 15...: return .cyan
        default: return Color(.systemGray4)
        }
    }
}

struct WeatherHourLabelsView: View {
    let ref: WeatherRef

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ref.hours, id: \.hour) { item in
                Text(item.hour % 4 == 2 ? String(item.hour) : " ")
                    .scaledFont(10)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct WeatherTilesView: View {
    let ref: WeatherRef

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            tile(L.t("weather_tile_rain"), "\(ref.hours.map(\.rain).max() ?? 0) %", "umbrella")
            tile(L.t("weather_tile_precip"),
                 "\((ref.hours.reduce(0) { $0 + $1.precip } * 10).rounded() / 10) mm", "drop")
            tile(L.t("weather_tile_uv"), WeatherAdviceRules.number(ref.hours.map(\.uv).max() ?? 0),
                 "sun.max")
            tile(L.t("weather_tile_gusts"),
                 "\(WeatherAdviceRules.number(ref.hours.map(\.gust).max() ?? 0)) km/h", "wind")
            tile(L.t("weather_tile_wind"),
                 "\(WeatherAdviceRules.number(ref.hours.map(\.wind).max() ?? 0)) km/h", "wind")
            tile(L.t("weather_tile_temp"), rangeText, "thermometer.medium")
        }
    }

    private func tile(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).scaledFont(10)
                Text(label)
                    .scaledFont(10.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color(.secondaryLabel))
            Text(value)
                .scaledFont(14, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemFill)))
    }

    private var rangeText: String {
        let temps = ref.hours.map(\.temp)
        return "\(WeatherAdviceRules.number(temps.min() ?? 0))–\(WeatherAdviceRules.number(temps.max() ?? 0)) °C"
    }
}

struct WeatherIconRow: View {
    let ref: WeatherRef

    var body: some View {
        HStack {
            ForEach(iconIndices, id: \.self) { index in
                if index < ref.hours.count {
                    VStack(spacing: 2) {
                        Image(systemName: ref.hours[index].kind.symbol)
                            .scaledFont(18)
                            .symbolRenderingMode(.multicolor)
                        Text("\(ref.hours[index].hour) h")
                            .scaledFont(10)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var iconIndices: [Int] {
        let wanted = [0, 4, 8, 12, 14, 16]
        return wanted.filter { $0 < ref.hours.count }
    }
}

struct WeatherHourScrubber: View {
    let ref: WeatherRef
    let selectedHour: Int
    let labelSize: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            WeatherCurveView(ref: ref, selectedHour: selectedHour, labelSize: labelSize)
            WeatherBarsView(ref: ref, selectedHour: selectedHour)
            WeatherHourLabelsView(ref: ref)
        }
        .overlay {
            WeatherHourScrubSurface(hours: ref.hours.map(\.hour), onSelect: onSelect)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: selectedHour)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L.t("weather_hour_picker")))
        .accessibilityValue(Text(WeatherAnswers.hourLine(ref, hour: selectedHour)))
        .accessibilityAdjustableAction(stepHour)
    }

    func stepHour(_ direction: AccessibilityAdjustmentDirection) {
        guard let index = ref.hours.firstIndex(where: { $0.hour == selectedHour }) else { return }
        switch direction {
        case .increment:
            onSelect(ref.hours[min(index + 1, ref.hours.count - 1)].hour)
        case .decrement:
            onSelect(ref.hours[max(index - 1, 0)].hour)
        @unknown default:
            break
        }
    }
}

private struct WeatherHourScrubSurface: UIViewRepresentable {
    let hours: [Int]
    let onSelect: (Int) -> Void

    func makeUIView(context: Context) -> WeatherScrubView {
        let view = WeatherScrubView()
        view.hours = hours
        view.onSelect = onSelect
        return view
    }

    func updateUIView(_ view: WeatherScrubView, context: Context) {
        view.hours = hours
        view.onSelect = onSelect
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WeatherScrubView,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 1, height: 1))
    }
}

final class WeatherScrubView: UIView, UIGestureRecognizerDelegate {
    var hours: [Int] = []
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    @objc func handleTap(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended else { return }
        pick(at: tap.location(in: self).x)
    }

    @objc func handlePan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .began || pan.state == .changed else { return }
        pick(at: pan.location(in: self).x)
    }

    func pick(at x: CGFloat) {
        guard let index = hourIndex(at: x) else { return }
        onSelect?(hours[index])
    }

    func hourIndex(at x: CGFloat) -> Int? {
        guard !hours.isEmpty else { return nil }
        guard hours.count > 1 else { return 0 }
        let count = CGFloat(hours.count)
        let column = max(0, (bounds.width - 2 * (count - 1)) / count)
        let step = column + 2
        guard step > 0 else { return nil }
        return min(hours.count - 1, max(0, Int(floor(max(0, x) / step))))
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return shouldScrub(velocity: pan.velocity(in: self))
    }

    func shouldScrub(velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

#if DEBUG
extension WeatherScrubView {
    func probeSelect(atX x: CGFloat) {
        pick(at: x)
    }

    func probeHour(atX x: CGFloat) -> Int? {
        guard let index = hourIndex(at: x) else { return nil }
        return hours[index]
    }
}
#endif
