import Foundation

/// Wakes an LG TV over the network by sending a Wake-on-LAN "magic packet".
/// The TV must have Quick Start+ / "Turn on via Wi-Fi" enabled in its settings.
public enum WakeOnLAN {
    /// Sends magic packets both to the broadcast address and directly to the TV's
    /// last known IP (LG TVs in Quick Start+ standby keep their network alive,
    /// so the unicast packet usually lands even where broadcast is filtered).
    @discardableResult
    public static func wake(macAddress: String, unicastHost: String? = nil) -> Bool {
        guard let packet = magicPacket(for: macAddress) else { return false }
        var delivered = false
        for _ in 0..<3 {
            if send(packet, to: "255.255.255.255", broadcast: true) { delivered = true }
            if let unicastHost, send(packet, to: unicastHost, broadcast: false) { delivered = true }
        }
        return delivered
    }

    static func magicPacket(for macAddress: String) -> Data? {
        let cleaned = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count == 12 else { return nil }
        var mac: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            mac.append(byte)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }
        return packet
    }

    private static func send(_ data: Data, to address: String, broadcast: Bool) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        if broadcast {
            var enable: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian
        addr.sin_addr.s_addr = inet_addr(address)
        guard addr.sin_addr.s_addr != INADDR_NONE else { return false }

        let sent = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            withUnsafePointer(to: addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, raw.baseAddress, data.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == data.count
    }
}
