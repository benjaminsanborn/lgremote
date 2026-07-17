import Foundation
import ActivityKit

/// Describes the Live Activity shown on the Lock Screen / Dynamic Island while
/// connected to a TV. The host + pairing key travel with the activity so the
/// interactive buttons can reach the TV without an App Group.
public struct TVActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var muted: Bool
        public init(muted: Bool = false) { self.muted = muted }
    }

    public var tvName: String
    public var host: String
    public var clientKey: String?

    public init(tvName: String, host: String, clientKey: String?) {
        self.tvName = tvName
        self.host = host
        self.clientKey = clientKey
    }
}
