import Foundation
import Network

/// Checks whether a TV is awake by seeing if its webOS control port accepts TCP connections.
public enum TVStatusProbe {
    public static func isAwake(host: String, timeout: TimeInterval = 2) async -> Bool {
        if await canConnect(host: host, port: 3001, timeout: timeout) { return true }
        // Older firmware only listens on the plaintext port.
        return await canConnect(host: host, port: 3000, timeout: timeout)
    }

    private static func canConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let resumed = OneShot()
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let finish: @Sendable (Bool) -> Void = { reachable in
                guard resumed.claim() else { return }
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

/// Guards a continuation against being resumed more than once.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
