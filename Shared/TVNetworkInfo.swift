import Foundation

/// Discovers a TV's real network MAC addresses via SSDP/UPnP: webOS TVs expose
/// <wifiMac> and <wiredMac> in their device-description XML. This is the only
/// reliable source — the SSAP "device_id" can be the wrong interface's MAC
/// (e.g. wired on a TV that's on Wi-Fi, whose radio then ignores wake packets),
/// and newer TVs 404 the connection-manager status call.
public enum TVNetworkInfo {
    public struct MACAddresses {
        public let wifi: String?
        public let wired: String?
    }

    /// SSDP-searches for the TV at `host` and reads its description XML.
    public static func macAddresses(host: String, timeout: TimeInterval = 3) async -> MACAddresses? {
        let locations = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            DispatchQueue.global().async {
                continuation.resume(returning: ssdpLocations(host: host, timeout: timeout))
            }
        }
        for location in locations {
            guard let url = URL(string: location),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let xml = String(decoding: data, as: UTF8.self)
            let wifi = tagValue("wifiMac", in: xml)
            let wired = tagValue("wiredMac", in: xml)
            if wifi != nil || wired != nil {
                return MACAddresses(wifi: wifi, wired: wired)
            }
        }
        return nil
    }

    private static func tagValue(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"), let close = xml.range(of: "</\(tag)>"),
              open.upperBound < close.lowerBound else { return nil }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Sends an SSDP M-SEARCH and collects LOCATION headers from responses
    /// sent by `host`. Multicast send requires the multicast entitlement.
    private static func ssdpLocations(host: String, timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var receiveTimeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        guard inet_pton(AF_INET, "239.255.255.250", &addr.sin_addr) == 1 else { return [] }

        let search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
        let payload = Array(search.utf8)
        let sent = withUnsafePointer(to: addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                sendto(fd, payload, payload.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == payload.count else { return [] }

        var locations: [String] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &fromLength)
                }
            }
            guard count > 0 else { continue }

            var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sourceAddress = from.sin_addr
            guard inet_ntop(AF_INET, &sourceAddress, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil,
                  String(cString: ipBuffer) == host else { continue }

            let response = String(decoding: buffer[0..<count], as: UTF8.self)
            for line in response.split(separator: "\r\n") {
                guard line.lowercased().hasPrefix("location:") else { continue }
                let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !locations.contains(value) { locations.append(value) }
            }
        }
        return locations
    }
}
