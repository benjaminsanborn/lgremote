import Foundation

public struct TVDevice: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// IP address or hostname on the local network.
    public var host: String
    /// Used for Wake-on-LAN power on. Auto-filled from the TV after first pairing.
    public var macAddress: String?
    /// The TV's other network interface (e.g. Ethernet when on Wi-Fi). Wake
    /// packets go to both so it doesn't matter which one is active.
    public var secondaryMACAddress: String?
    /// webOS pairing key. Nil until the TV prompt has been accepted once.
    public var clientKey: String?

    public init(id: UUID = UUID(), name: String, host: String, macAddress: String? = nil,
                secondaryMACAddress: String? = nil, clientKey: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.macAddress = macAddress
        self.secondaryMACAddress = secondaryMACAddress
        self.clientKey = clientKey
    }

    /// Every MAC worth sending a magic packet to.
    public var wakeMACAddresses: [String] {
        [macAddress, secondaryMACAddress].compactMap { $0 }
    }
}

public enum TVStore {
    private static let tvsKey = "tvs"
    private static let selectedKey = "selectedTVID"

    public static var defaults: UserDefaults { .standard }

    /// TVs (including webOS pairing keys) live in the Keychain so they survive
    /// reinstalls and new builds — UserDefaults is wiped when a differently-signed
    /// build replaces the app, which forced re-pairing on every install.
    public static func loadTVs() -> [TVDevice] {
        if let data = KeychainStore.read(key: tvsKey),
           let tvs = try? JSONDecoder().decode([TVDevice].self, from: data) {
            return tvs
        }
        // Migrate from the old UserDefaults storage.
        guard let data = defaults.data(forKey: tvsKey),
              let tvs = try? JSONDecoder().decode([TVDevice].self, from: data) else { return [] }
        saveTVs(tvs)
        return tvs
    }

    public static func saveTVs(_ tvs: [TVDevice]) {
        guard let data = try? JSONEncoder().encode(tvs) else { return }
        KeychainStore.write(key: tvsKey, data: data)
        defaults.set(data, forKey: tvsKey)
    }

    public static var selectedTVID: UUID? {
        get { defaults.string(forKey: selectedKey).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: selectedKey) }
    }

    /// The explicitly selected TV, else the first saved one.
    public static var selectedTV: TVDevice? {
        let tvs = loadTVs()
        if let id = selectedTVID, let tv = tvs.first(where: { $0.id == id }) { return tv }
        return tvs.first
    }

    public static func update(_ tv: TVDevice) {
        var tvs = loadTVs()
        if let index = tvs.firstIndex(where: { $0.id == tv.id }) {
            tvs[index] = tv
        } else {
            tvs.append(tv)
        }
        saveTVs(tvs)
    }
}
