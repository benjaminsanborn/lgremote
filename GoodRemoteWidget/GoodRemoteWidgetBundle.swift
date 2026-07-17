import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct GoodRemoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        TVLiveActivity()
    }
}

struct TVLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TVActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(context.attributes.tvName, systemImage: "tv")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                controls(context.attributes, size: 34)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.tvName, systemImage: "tv")
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(context.attributes, size: 38)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "tv")
            } compactTrailing: {
                Image(systemName: "play.fill")
            } minimal: {
                Image(systemName: "tv")
            }
        }
    }

    @ViewBuilder
    private func controls(_ tv: TVActivityAttributes, size: CGFloat) -> some View {
        HStack(spacing: 12) {
            iconButton("speaker.wave.1.fill", intent: TVVolumeDownIntent(host: tv.host, clientKey: tv.clientKey), size: size)
            iconButton("play.fill", intent: TVPlayIntent(host: tv.host, clientKey: tv.clientKey), size: size)
            iconButton("pause.fill", intent: TVPauseIntent(host: tv.host, clientKey: tv.clientKey), size: size)
            iconButton("speaker.wave.3.fill", intent: TVVolumeUpIntent(host: tv.host, clientKey: tv.clientKey), size: size)
        }
    }

    private func iconButton<I: AppIntent>(_ system: String, intent: I, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: system)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}
