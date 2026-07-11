import Foundation

public struct TVInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct TVLaunchPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public extension WebOSClient {
    // Audio
    func volumeUp() async throws { try await request("ssap://audio/volumeUp") }
    func volumeDown() async throws { try await request("ssap://audio/volumeDown") }
    func setMute(_ mute: Bool) async throws { try await request("ssap://audio/setMute", payload: ["mute": mute]) }

    func isMuted() async throws -> Bool {
        let payload = try await request("ssap://audio/getStatus")
        if let mute = payload["mute"] as? Bool { return mute }
        if let volumeStatus = payload["volumeStatus"] as? [String: Any], let mute = volumeStatus["muteStatus"] as? Bool { return mute }
        return false
    }

    func toggleMute() async throws {
        let muted = try await isMuted()
        try await setMute(!muted)
    }

    // Power
    func turnOff() async throws { try await request("ssap://system/turnOff") }

    /// Wakes the panel when the TV is reachable but in standby (Quick Start+
    /// keeps webOS listening with the screen off).
    func turnOnScreen() async throws { try await request("ssap://com.webos.service.tvpower/power/turnOnScreen") }

    /// e.g. "Active", "Active Standby", "Suspend", "Screen Saver"
    func powerState() async throws -> String {
        let payload = try await request("ssap://com.webos.service.tvpower/power/getPowerState")
        return payload["state"] as? String ?? "Unknown"
    }

    // Channels
    func channelUp() async throws { try await request("ssap://tv/channelUp") }
    func channelDown() async throws { try await request("ssap://tv/channelDown") }

    // Media
    func play() async throws { try await request("ssap://media.controls/play") }
    func pause() async throws { try await request("ssap://media.controls/pause") }
    func stop() async throws { try await request("ssap://media.controls/stop") }
    func rewind() async throws { try await request("ssap://media.controls/rewind") }
    func fastForward() async throws { try await request("ssap://media.controls/fastForward") }

    // Apps & inputs
    func launchApp(id: String) async throws {
        try await request("ssap://system.launcher/launch", payload: ["id": id])
    }

    func switchInput(id: String) async throws {
        try await request("ssap://tv/switchInput", payload: ["inputId": id])
    }

    func listInputs() async throws -> [TVInput] {
        let payload = try await request("ssap://tv/getExternalInputList")
        let devices = payload["devices"] as? [[String: Any]] ?? []
        return devices.compactMap { device in
            guard let id = device["id"] as? String else { return nil }
            let label = (device["label"] as? String) ?? id
            return TVInput(id: id, label: label)
        }
    }

    func listApps() async throws -> [TVLaunchPoint] {
        let payload = try await request("ssap://com.webos.applicationManager/listLaunchPoints")
        let points = payload["launchPoints"] as? [[String: Any]] ?? []
        return points.compactMap { point in
            guard let id = point["id"] as? String, let title = point["title"] as? String else { return nil }
            return TVLaunchPoint(id: id, title: title)
        }
    }

    /// The MAC address to target with Wake-on-LAN: the active network
    /// interface's MAC from the connection manager. The software-info
    /// "device_id" is NOT reliable for this — it can be a different
    /// interface's MAC (e.g. Ethernet on a TV that's on Wi-Fi), and magic
    /// packets addressed to it are silently ignored.
    func wakeMACAddress() async throws -> String? {
        if let payload = try? await request("ssap://com.webos.service.connectionmanager/getStatus") {
            func section(_ key: String) -> [String: Any]? { payload[key] as? [String: Any] }
            let wifiMAC = section("wifiInfo")?["macAddress"] as? String
            let wiredMAC = section("wiredInfo")?["macAddress"] as? String
            let wiredConnected = (section("wired")?["state"] as? String) == "connected"
            let wifiConnected = (section("wifi")?["state"] as? String) == "connected"
            if wiredConnected, let wiredMAC { return wiredMAC }
            if wifiConnected, let wifiMAC { return wifiMAC }
            if let mac = wifiMAC ?? wiredMAC { return mac }
        }
        // Last resort for firmware without getStatus MAC fields.
        let payload = try await request("ssap://com.webos.service.update/getCurrentSWInformation")
        return payload["device_id"] as? String
    }
}
