import Foundation
import Network

/// Finds LG TVs on the local network via Bonjour (no restricted multicast
/// entitlement needed). Browses the webOS "second screen" service plus AirPlay —
/// some LG models only advertise the latter — filtering AirPlay results to LG
/// devices via their TXT record so HomePods and Apple TVs don't show up.
@MainActor
final class TVDiscovery: ObservableObject {
    struct FoundTV: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
        static func == (lhs: FoundTV, rhs: FoundTV) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    @Published var found: [FoundTV] = []
    @Published var isBrowsing = false

    private var browsers: [NWBrowser] = []
    private var resultsByType: [String: [FoundTV]] = [:]

    private nonisolated static let webOSType = "_webos-second-screen._tcp"
    private nonisolated static let airplayType = "_airplay._tcp"
    private static let serviceTypes = [webOSType, airplayType]

    func start() {
        stop()
        isBrowsing = true
        for type in Self.serviceTypes {
            // TXT records are needed to tell LG TVs apart from other AirPlay devices.
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: NWParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let items: [FoundTV] = results.compactMap { result in
                    guard case let .service(name, serviceType, _, _) = result.endpoint else { return nil }
                    if serviceType.hasPrefix(Self.airplayType), !Self.looksLikeLGTV(result: result, name: name) {
                        return nil
                    }
                    return FoundTV(id: "\(serviceType)|\(name)", name: name, endpoint: result.endpoint)
                }
                Task { @MainActor [weak self] in
                    self?.update(items, forType: type)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    /// LG TVs advertise AirPlay with TXT entries like "manufacturer=LG Electronics"
    /// and "model=OLED55C3PUA"; fall back to the advertised name.
    private nonisolated static func looksLikeLGTV(result: NWBrowser.Result, name: String) -> Bool {
        var fields = [name]
        if case let .bonjour(txt) = result.metadata {
            fields.append(contentsOf: [txt["manufacturer"], txt["model"], txt["fv"]].compactMap { $0 })
        }
        return fields.contains { field in
            let value = field.lowercased()
            return value.contains("lg ") || value.hasPrefix("lg") || value.contains("[lg]")
                || value.contains("webos") || value.hasPrefix("oled") || value.contains("lge ")
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        resultsByType = [:]
        found = []
        isBrowsing = false
    }

    private func update(_ items: [FoundTV], forType type: String) {
        resultsByType[type] = items
        // webos-second-screen results first, then LG AirPlay entries not already listed.
        var merged: [FoundTV] = resultsByType[Self.webOSType] ?? []
        for item in resultsByType[Self.airplayType] ?? [] where !merged.contains(where: { $0.name == item.name }) {
            merged.append(item)
        }
        found = merged
    }

    /// Resolves a Bonjour endpoint to an IP address by opening a throwaway TCP
    /// connection and reading the remote address it lands on.
    nonisolated static func resolveHost(for endpoint: NWEndpoint) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "tv-resolve")
            let parameters = NWParameters.tcp
            if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOptions.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: parameters)
            final class Flag: @unchecked Sendable { var finished = false }
            let flag = Flag()

            @Sendable func finish(_ host: String?) {
                queue.async {
                    guard !flag.finished else { return }
                    flag.finished = true
                    connection.cancel()
                    continuation.resume(returning: host)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint {
                        switch host {
                        case .ipv4(let address):
                            finish("\(address)".components(separatedBy: "%").first)
                        case .ipv6(let address):
                            finish("\(address)".components(separatedBy: "%").first)
                        case .name(let name, _):
                            finish(name)
                        @unknown default:
                            finish(nil)
                        }
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }
}
