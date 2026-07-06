import Foundation
import SwiftUI

@MainActor
final class RemoteViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case pairing
        case connected

        var label: String {
            switch self {
            case .disconnected: return "Not Connected"
            case .connecting: return "Connecting…"
            case .pairing: return "Pairing…"
            case .connected: return "Connected"
            }
        }
    }

    @Published var tvs: [TVDevice] = TVStore.loadTVs()
    @Published var selectedID: UUID? = TVStore.selectedTVID
    @Published var state: ConnectionState = .disconnected
    @Published var errorMessage: String?
    @Published var inputs: [TVInput] = []
    @Published var apps: [TVLaunchPoint] = []
    @Published var showSetup = false
    /// Launch screen: pick a TV (and wake it) before showing the remote.
    @Published var showPicker = false
    /// Live per-TV power status from probing the webOS port. Missing = unknown.
    @Published var awake: [UUID: Bool] = [:]

    private let client = WebOSClient()
    private var connectTask: Task<Void, Never>?

    var selectedTV: TVDevice? {
        if let id = selectedID, let tv = tvs.first(where: { $0.id == id }) { return tv }
        return tvs.first
    }

    init() {
        if selectedID == nil { selectedID = tvs.first?.id }
        if tvs.isEmpty { showSetup = true }
        showPicker = !tvs.isEmpty
        let client = client
        Task {
            await client.setOnUnexpectedDisconnect { [weak self] in
                Task { @MainActor [weak self] in self?.socketDropped() }
            }
        }
    }

    /// The control socket died (TV powered off, app was suspended, network blip).
    /// Optimistically try to get back — if the TV is gone the attempt just times out.
    private func socketDropped() {
        guard state == .connected else { return }
        connect()
    }

    private func persist() {
        TVStore.saveTVs(tvs)
        TVStore.selectedTVID = selectedID
    }

    // MARK: TV management

    func select(_ tv: TVDevice) {
        selectedID = tv.id
        persist()
        connect()
    }

    func addTV(name: String, host: String, mac: String?) {
        let trimmedMAC = mac?.trimmingCharacters(in: .whitespaces)
        let tv = TVDevice(name: name.isEmpty ? "LG TV" : name,
                          host: host.trimmingCharacters(in: .whitespaces),
                          macAddress: (trimmedMAC?.isEmpty ?? true) ? nil : trimmedMAC)
        tvs.append(tv)
        select(tv)
    }

    func updateTV(_ tv: TVDevice) {
        guard let index = tvs.firstIndex(where: { $0.id == tv.id }) else { return }
        let hostChanged = tvs[index].host != tv.host
        tvs[index] = tv
        persist()
        if tv.id == selectedTV?.id && hostChanged { connect() }
    }

    func removeTV(_ tv: TVDevice) {
        tvs.removeAll { $0.id == tv.id }
        if selectedID == tv.id {
            selectedID = tvs.first?.id
            connect()
        }
        persist()
        if tvs.isEmpty { showSetup = true }
    }

    // MARK: Connection

    func connect() {
        connectTask?.cancel()
        inputs = []
        apps = []
        guard let tv = selectedTV else {
            state = .disconnected
            return
        }
        state = tv.clientKey == nil ? .pairing : .connecting
        connectTask = Task {
            _ = await performConnect(tv)
        }
    }

    /// One connection attempt: connect + register, then post-connect housekeeping.
    /// Sets `.connected` on success. On failure sets `.disconnected` (and surfaces
    /// errors) only when `reportFailure` is true, so retry loops can keep the UI
    /// in "Connecting…" between attempts. Pairing rejection is always surfaced.
    private func performConnect(_ tv: TVDevice, reportFailure: Bool = true) async -> Bool {
        do {
            let key = try await client.connect(host: tv.host, clientKey: tv.clientKey)
            guard !Task.isCancelled else { return false }
            state = .connected
            awake[tv.id] = true
            showPicker = false

            var updated = tv
            updated.clientKey = key
            if updated.macAddress == nil {
                updated.macAddress = try? await client.deviceMACAddress()
            }
            if updated != tv { updateTV(updated) }

            // Quick Start+ standby accepts connections with the panel off —
            // if the TV isn't fully awake, turn its screen on.
            if let power = try? await client.powerState(), power != "Active" {
                try? await client.turnOnScreen()
                if let mac = updated.macAddress {
                    WakeOnLAN.wake(macAddress: mac, unicastHost: updated.host)
                }
            }

            inputs = (try? await client.listInputs()) ?? []
            apps = ((try? await client.listApps()) ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            if case WebOSError.pairingRejected = error {
                state = .disconnected
                errorMessage = error.localizedDescription
                return false
            }
            if reportFailure {
                state = .disconnected
                if tv.clientKey == nil {
                    errorMessage = "Couldn't pair with \"\(tv.name)\". Make sure the TV is on and on the same Wi-Fi network, then tap the status indicator to retry."
                }
            }
            return false
        }
    }

    func connectIfNeeded() {
        guard selectedTV != nil else { return }
        switch state {
        case .disconnected:
            connect()
        case .connected:
            // The socket may have silently died while the app was suspended —
            // verify with a cheap request and reconnect if it's actually dead.
            let client = client
            Task {
                if await client.isConnected == false {
                    connect()
                    return
                }
                do {
                    _ = try await client.request("ssap://com.webos.service.tvpower/power/getPowerState", timeout: 3)
                } catch {
                    guard state == .connected else { return }
                    connect()
                }
            }
        case .connecting, .pairing:
            break
        }
    }

    /// Probes every saved TV so the picker can show live power status.
    func refreshStatuses() {
        for tv in tvs {
            Task {
                let isAwake = await TVStatusProbe.isAwake(host: tv.host)
                awake[tv.id] = isAwake
            }
        }
    }

    /// Selects the TV, wakes it if it's asleep (Wake-on-LAN + retry until its
    /// webOS port responds), then connects. This is what the picker and the
    /// power button use — a single WoL shot followed by one connect attempt
    /// misses TVs that take 10+ seconds to boot their network stack.
    func wakeAndConnect(_ tv: TVDevice) {
        selectedID = tv.id
        persist()
        connectTask?.cancel()
        inputs = []
        apps = []
        errorMessage = nil
        state = .connecting
        connectTask = Task {
            // Always send wake packets up front: with Quick Start+ the TV keeps its
            // webOS port open while the screen is off, so a reachable port does NOT
            // mean the TV is on. WoL is harmless if it already is.
            let reachable = await TVStatusProbe.isAwake(host: tv.host)
            guard !Task.isCancelled else { return }
            awake[tv.id] = reachable
            if tv.macAddress == nil && !reachable {
                state = .disconnected
                errorMessage = "\"\(tv.name)\" is off and has no saved MAC address, so it can't be woken remotely. Connect once while it's on (the MAC is saved automatically) or enter it manually in TV settings."
                return
            }
            // Keep waking and retrying for ~30 seconds — a TV coming out of
            // standby accepts wake packets well before its websocket is ready,
            // so single-shot attempts fail spuriously. Each cycle: wake packets,
            // a cheap port probe (2s timeout), and a full connect only once the
            // port answers.
            for _ in 0..<10 {
                if let mac = tv.macAddress {
                    WakeOnLAN.wake(macAddress: mac, unicastHost: tv.host)
                }
                if await TVStatusProbe.isAwake(host: tv.host) {
                    if Task.isCancelled { return }
                    awake[tv.id] = true
                    if await performConnect(tv, reportFailure: false) { return }
                    // performConnect only reports terminal failures (pairing rejected).
                    if state == .disconnected { return }
                }
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            state = .disconnected
            let report = WakeOnLAN.lastReport.joined(separator: "\n")
            errorMessage = "Couldn't reach \"\(tv.name)\". Make sure the TV is plugged in, on the same network, and has \"Turn on via Wi-Fi\" (Quick Start+) enabled in its settings.\n\nWake packet log:\n\(report)"
        }
    }

    // MARK: Commands

    /// Runs a command, surfacing errors. If the socket died, optimistically
    /// reconnects instead of leaving the remote stuck on "Not Connected".
    func run(_ operation: @escaping @Sendable (WebOSClient) async throws -> Void) {
        let client = client
        Task {
            do {
                try await operation(client)
            } catch {
                if await client.isConnected == false {
                    // Reconnect unless an attempt is already in flight.
                    if state == .connected || state == .disconnected { connect() }
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func button(_ name: String) {
        run { try await $0.sendButton(name) }
    }

    func powerToggle() {
        guard let tv = selectedTV else { return }
        Task {
            if state == .connected {
                do {
                    try await client.turnOff()
                    await client.disconnect()
                    state = .disconnected
                    awake[tv.id] = false
                    return
                } catch {
                    // Fall through and try waking instead.
                }
            }
            wakeAndConnect(tv)
        }
    }
}
