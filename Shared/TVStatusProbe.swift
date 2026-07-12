import Foundation
import Network

/// Checks whether a TV is awake by seeing if its webOS control port accepts TCP connections.
public enum TVStatusProbe {
    /// Probes the secure (3001) and legacy plaintext (3000) webOS ports at the
    /// same time and returns as soon as either answers, so an off TV is
    /// reported in one timeout rather than two sequential ones.
    public static func isAwake(host: String, timeout: TimeInterval = 1.5) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await canConnect(host: host, port: 3001, timeout: timeout) }
            group.addTask { await canConnect(host: host, port: 3000, timeout: timeout) }
            for await reachable in group where reachable {
                group.cancelAll()
                return true
            }
            return false
        }
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
