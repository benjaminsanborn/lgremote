import Foundation

public struct TVDevice: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// IP address or hostname on the local network.
    public var host: String
    /// Used for Wake-on-LAN power on. Auto-filled from the TV after first pairing.
    public var macAddress: String?
    /// webOS pairing key. Nil until the TV prompt has been accepted once.
    public var clientKey: String?

    public init(id: UUID = UUID(), name: String, host: String, macAddress: String? = nil, clientKey: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.macAddress = macAddress
        self.clientKey = clientKey
    }
}

public enum TVStore {
    private static let tvsKey = "tvs"
    private static let selectedKey = "selectedTVID"

    public static var defaults: UserDefaults { .standard }

    public static func loadTVs() -> [TVDevice] {
        guard let data = defaults.data(forKey: tvsKey),
              let tvs = try? JSONDecoder().decode([TVDevice].self, from: data) else { return [] }
        return tvs
    }

    public static func saveTVs(_ tvs: [TVDevice]) {
        guard let data = try? JSONEncoder().encode(tvs) else { return }
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
