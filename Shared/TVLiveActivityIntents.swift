import AppIntents
import Foundation

/// Caches one connection per process so consecutive Live Activity button presses
/// don't each pay the full connect+register cost.
actor TVQuickControl {
    static let shared = TVQuickControl()
    private var client: WebOSClient?
    private var host: String?

    func perform(host: String, clientKey: String?,
                 _ action: @Sendable (WebOSClient) async throws -> Void) async {
        if self.host != host {
            await client?.disconnect()
            client = nil
            self.host = host
        }
        var alive = false
        if let client { alive = await client.isConnected }
        if !alive {
            let fresh = WebOSClient()
            do { _ = try await fresh.connect(host: host, clientKey: clientKey) }
            catch { return }
            client = fresh
        }
        guard let client else { return }
        do { try await action(client) }
        catch { self.client = nil } // drop a dead socket so the next press reconnects
    }
}

// LiveActivityIntent runs in the app's process (woken as needed) rather than the
// widget extension, and is App Store-sanctioned for Live Activity buttons.

/// Sends a pointer-socket button (UP/DOWN/LEFT/RIGHT/ENTER/HOME/BACK/…).
public struct TVButtonIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Remote Button"
    @Parameter(title: "Host") public var host: String
    @Parameter(title: "Key") public var clientKey: String?
    @Parameter(title: "Button") public var button: String
    public init() {}
    public init(host: String, clientKey: String?, button: String) {
        self.host = host; self.clientKey = clientKey; self.button = button
    }
    public func perform() async throws -> some IntentResult {
        let name = button
        await TVQuickControl.shared.perform(host: host, clientKey: clientKey) { try await $0.sendButton(name) }
        return .result()
    }
}

public struct TVPlayIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Play"
    @Parameter(title: "Host") public var host: String
    @Parameter(title: "Key") public var clientKey: String?
    public init() {}
    public init(host: String, clientKey: String?) { self.host = host; self.clientKey = clientKey }
    public func perform() async throws -> some IntentResult {
        await TVQuickControl.shared.perform(host: host, clientKey: clientKey) { try await $0.play() }
        return .result()
    }
}

public struct TVPauseIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Pause"
    @Parameter(title: "Host") public var host: String
    @Parameter(title: "Key") public var clientKey: String?
    public init() {}
    public init(host: String, clientKey: String?) { self.host = host; self.clientKey = clientKey }
    public func perform() async throws -> some IntentResult {
        await TVQuickControl.shared.perform(host: host, clientKey: clientKey) { try await $0.pause() }
        return .result()
    }
}

public struct TVVolumeUpIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Volume Up"
    @Parameter(title: "Host") public var host: String
    @Parameter(title: "Key") public var clientKey: String?
    public init() {}
    public init(host: String, clientKey: String?) { self.host = host; self.clientKey = clientKey }
    public func perform() async throws -> some IntentResult {
        await TVQuickControl.shared.perform(host: host, clientKey: clientKey) { try await $0.volumeUp() }
        return .result()
    }
}

public struct TVVolumeDownIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Volume Down"
    @Parameter(title: "Host") public var host: String
    @Parameter(title: "Key") public var clientKey: String?
    public init() {}
    public init(host: String, clientKey: String?) { self.host = host; self.clientKey = clientKey }
    public func perform() async throws -> some IntentResult {
        await TVQuickControl.shared.perform(host: host, clientKey: clientKey) { try await $0.volumeDown() }
        return .result()
    }
}
