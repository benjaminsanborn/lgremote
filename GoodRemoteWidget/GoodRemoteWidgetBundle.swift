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
            // Lock Screen / banner — a single row: Vol−, Vol+, Back, OK.
            lockRow(context.attributes, size: 46)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
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

    // Simple single row for the Lock Screen: Vol−, Vol+, Back, OK.
    private func lockRow(_ tv: TVActivityAttributes, size: CGFloat) -> some View {
        HStack(spacing: 14) {
            iconButton("speaker.wave.1.fill", TVVolumeDownIntent(host: tv.host, clientKey: tv.clientKey), size)
            iconButton("speaker.wave.3.fill", TVVolumeUpIntent(host: tv.host, clientKey: tv.clientKey), size)
            iconButton("arrow.uturn.backward", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "BACK"), size)
            okButton(TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "ENTER"), size)
        }
    }

    // Volume stacked on the left, Home/Back in the middle, d-pad cross on the right.
    private func pad(_ tv: TVActivityAttributes, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 8) {
                iconButton("speaker.wave.3.fill", TVVolumeUpIntent(host: tv.host, clientKey: tv.clientKey), size)
                iconButton("speaker.wave.1.fill", TVVolumeDownIntent(host: tv.host, clientKey: tv.clientKey), size)
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                iconButton("house.fill", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "HOME"), size)
                iconButton("arrow.uturn.backward", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "BACK"), size)
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                iconButton("chevron.up", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "UP"), size)
                HStack(spacing: 6) {
                    iconButton("chevron.left", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "LEFT"), size)
                    okButton(TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "ENTER"), size)
                    iconButton("chevron.right", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "RIGHT"), size)
                }
                iconButton("chevron.down", TVButtonIntent(host: tv.host, clientKey: tv.clientKey, button: "DOWN"), size)
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
