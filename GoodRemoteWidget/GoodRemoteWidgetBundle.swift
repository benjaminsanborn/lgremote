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
            VStack(spacing: 6) {
                Label(context.attributes.tvName, systemImage: "tv")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                pad(context.attributes, size: 34)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
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
                    pad(context.attributes, size: 32)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "tv")
            } compactTrailing: {
                Image(systemName: "chevron.up.chevron.down")
            } minimal: {
                Image(systemName: "tv")
            }
        }
    }

    // 3×3 control cluster: d-pad cross in the center, Home/Back on top, volume on the bottom.
    private func pad(_ tv: TVActivityAttributes, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                iconButton("house.fill", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "HOME"), size)
                iconButton("chevron.up", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "UP"), size)
                iconButton("arrow.uturn.backward", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "BACK"), size)
            }
            HStack(spacing: 6) {
                iconButton("chevron.left", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "LEFT"), size)
                okButton(TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "ENTER"), size)
                iconButton("chevron.right", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "RIGHT"), size)
            }
            HStack(spacing: 6) {
                iconButton("speaker.wave.1.fill", TVVolumeDownIntent(host: tv.host, clientKey: tv.clientKey), size)
                iconButton("chevron.down", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "DOWN"), size)
                iconButton("speaker.wave.3.fill", TVVolumeUpIntent(host: tv.host, clientKey: tv.clientKey), size)
            }
        }
    }

    private func iconButton<I: AppIntent>(_ system: String, _ intent: I, _ size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: system)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private func okButton<I: AppIntent>(_ intent: I, _ size: CGFloat) -> some View {
        Button(intent: intent) {
            Text("OK")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
        }
        .buttonStyle(.plain)
    }
}
