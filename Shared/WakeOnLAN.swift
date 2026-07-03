import Foundation

/// Wakes an LG TV over the network by sending a Wake-on-LAN "magic packet".
/// The TV must have Quick Start+ / "Turn on via Wi-Fi" enabled in its settings.
public enum WakeOnLAN {
    /// Sends magic packets to the subnet-directed broadcast address (computed from
    /// the phone's own interfaces), the global broadcast, and directly to the TV's
    /// last known IP. Global broadcast is filtered by many routers and the unicast
    /// packet is dropped once the sleeping TV's ARP entry expires, so the subnet
    /// broadcast is the one that reliably reaches a deep-sleeping TV. Sent on both
    /// common WoL ports (9 and 7).
    @discardableResult
    public static func wake(macAddress: String, unicastHost: String? = nil) -> Bool {
        guard let packet = magicPacket(for: macAddress) else { return false }
        var targets = broadcastAddresses()
        if let unicastHost { targets.append(unicastHost) }
        var delivered = false
        for _ in 0..<3 {
            for target in targets {
                let isBroadcast = target.hasSuffix(".255") || target == "255.255.255.255"
                for port in [UInt16(9), UInt16(7)] {
                    if send(packet, to: target, port: port, broadcast: isBroadcast) { delivered = true }
                }
            }
        }
        return delivered
    }

    /// The IPv4 broadcast addresses of the device's active interfaces, plus the
    /// global broadcast address.
    static func broadcastAddresses() -> [String] {
        var addresses: Set<String> = ["255.255.255.255"]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return Array(addresses) }
        defer { freeifaddrs(first) }
        var pointer = first
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard (Int32(interface.ifa_flags) & IFF_BROADCAST) != 0,
                  (Int32(interface.ifa_flags) & IFF_UP) != 0,
                  let broadcast = interface.ifa_dstaddr,
                  broadcast.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var addr = sockaddr_in()
            memcpy(&addr, broadcast, MemoryLayout<sockaddr_in>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sin = addr.sin_addr
            if inet_ntop(AF_INET, &sin, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                addresses.insert(String(cString: buffer))
            }
        }
        return Array(addresses)
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

    private static func send(_ data: Data, to address: String, port: UInt16 = 9, broadcast: Bool) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        if broadcast {
            var enable: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
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
