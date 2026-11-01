import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningActivityAttributes.self) { context in
            ListeningActivityCard(mode: context.attributes.mode, state: context.state)
                .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "gwenmobile://live"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ListeningActivityOrb(mode: context.attributes.mode, phase: context.state.phase, size: 32)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ListeningActivityTimer(startedAt: context.state.startedAt)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(verbatim: context.state.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            } compactLeading: {
                ListeningActivityOrb(mode: context.attributes.mode, phase: context.state.phase, size: 20)
            } compactTrailing: {
                ListeningActivityTimer(startedAt: context.state.startedAt, compact: true)
            } minimal: {
                ListeningActivityOrb(mode: context.attributes.mode, phase: context.state.phase, size: 20)
            }
            .keylineTint(.purple)
        }
    }
}

struct ListeningActivityCard: View {
    let mode: ListeningActivityAttributes.Mode
    let state: ListeningActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ListeningActivityOrb(mode: mode, phase: state.phase, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ListeningActivityTimer(startedAt: state.startedAt)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(ListeningActivityPalette.rainbowGradient, lineWidth: 1.5)
        }
    }
}

struct ListeningActivityOrb: View {
    let mode: ListeningActivityAttributes.Mode
    let phase: ListeningActivityAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ListeningActivityPalette.rainbowGradient, lineWidth: max(1.5, size * 0.08))
            Image(systemName: symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var symbolName: String {
        switch phase {
        case .armed:
            return mode == .conversation ? "waveform" : "mic.fill"
        case .recording:
            return "waveform"
        case .processing:
            return "sparkles"
        }
    }
}

struct ListeningActivityTimer: View {
    let startedAt: Date
    var compact = false

    var body: some View {
        Text(startedAt, style: .timer)
            .font((compact ? Font.caption2 : Font.caption).monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
    }
}
