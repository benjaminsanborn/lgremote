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
    /// Per-target result of the most recent wake() call, e.g.
    /// "192.168.1.255:9 ok" or "255.255.255.255:9 errno 1 (EPERM)".
    public private(set) static var lastReport: [String] = []

    @discardableResult
    public static func wake(macAddress: String, unicastHost: String? = nil) -> Bool {
        guard let packet = magicPacket(for: macAddress) else {
            lastReport = ["invalid MAC \(macAddress)"]
            return false
        }
        // (address, interface to bind, broadcast). The global broadcast MUST be
        // bound to a specific interface — an unbound sendto 255.255.255.255
        // fails with EHOSTUNREACH on iOS.
        var sends: [(address: String, interface: String?, localAddress: String?, broadcast: Bool)] = []
        for interface in broadcastInterfaces() {
            sends.append((interface.broadcast, nil, nil, true))
            sends.append(("255.255.255.255", interface.name, interface.localAddress, true))
        }
        if let unicastHost { sends.append((unicastHost, nil, nil, false)) }

        var delivered = false
        var report: [String] = []
        for round in 0..<3 {
            for target in sends {
                for port in [UInt16(9), UInt16(7)] {
                    let result = send(packet, to: target.address, port: port,
                                      broadcast: target.broadcast, interface: target.interface,
                                      localAddress: target.localAddress)
                    if result == nil { delivered = true }
                    if round == 0 {
                        let via = target.interface.map { "@\($0)" } ?? ""
                        report.append("\(target.address)\(via):\(port) \(result ?? "ok")")
                    }
                }
            }
        }
        lastReport = report
        return delivered
    }

    struct BroadcastInterface {
        let name: String
        let broadcast: String
        let localAddress: String
    }

    /// The device's active broadcast-capable IPv4 interfaces (e.g. Wi-Fi "en0")
    /// with their subnet broadcast addresses.
    static func broadcastInterfaces() -> [BroadcastInterface] {
        var result: [BroadcastInterface] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return result }
        defer { freeifaddrs(first) }
        var pointer = first
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard (Int32(interface.ifa_flags) & IFF_BROADCAST) != 0,
                  (Int32(interface.ifa_flags) & IFF_UP) != 0,
                  let broadcast = interface.ifa_dstaddr,
                  broadcast.pointee.sa_family == sa_family_t(AF_INET),
                  let local = interface.ifa_addr,
                  local.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            func string(from sockaddr: UnsafeMutablePointer<sockaddr>) -> String? {
                var addr = sockaddr_in()
                memcpy(&addr, sockaddr, MemoryLayout<sockaddr_in>.size)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sin = addr.sin_addr
                guard inet_ntop(AF_INET, &sin, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let broadcastString = string(from: broadcast), let localString = string(from: local) {
                result.append(BroadcastInterface(name: String(cString: interface.ifa_name),
                                                 broadcast: broadcastString,
                                                 localAddress: localString))
            }
        }
        return result
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

    /// Returns nil on success, or a short error description.
    private static func send(_ data: Data, to address: String, port: UInt16 = 9,
                             broadcast: Bool, interface: String? = nil, localAddress: String? = nil) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return "socket errno \(errno)" }
        defer { close(fd) }

        if broadcast {
            var enable: Int32 = 1
            if setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) != 0 {
                return "SO_BROADCAST errno \(errno)"
            }
        }

        if let interface {
            var index = if_nametoindex(interface)
            guard index != 0 else { return "no interface \(interface)" }
            if setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) != 0 {
                return "IP_BOUND_IF errno \(errno)"
            }
        }

        // Global broadcast also needs the socket bound to the interface's own
        // address, or the kernel can't pick a source and fails with EHOSTUNREACH.
        if let localAddress {
            var local = sockaddr_in()
            local.sin_family = sa_family_t(AF_INET)
            local.sin_port = 0
            guard inet_pton(AF_INET, localAddress, &local.sin_addr) == 1 else { return "bad local address" }
            let bound = withUnsafePointer(to: local) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound != 0 { return "bind errno \(errno)" }
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        // inet_pton, not inet_addr: inet_addr("255.255.255.255") == INADDR_NONE,
        // so the error check would reject the global broadcast address itself.
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else { return "bad address" }

        let sent = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            withUnsafePointer(to: addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, raw.baseAddress, data.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent == data.count { return nil }
        return "sendto errno \(errno) (\(String(cString: strerror(errno))))"
    }
}
