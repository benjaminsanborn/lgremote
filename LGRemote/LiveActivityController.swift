import Foundation
import ActivityKit

/// Manages the Lock Screen / Dynamic Island Live Activity for the connected TV.
enum TVLiveActivity {
    /// Starts (or restarts) the activity for `tv`. No-op if Live Activities are
    /// disabled by the user. Must be called while the app is foreground.
    static func start(tv: TVDevice) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attributes = TVActivityAttributes(tvName: tv.name, host: tv.host, clientKey: tv.clientKey)
        let content = ActivityContent(state: TVActivityAttributes.ContentState(), staleDate: nil)
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    /// Ends every running TV activity.
    static func end() {
        for activity in Activity<TVActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
