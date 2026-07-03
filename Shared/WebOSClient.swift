import Foundation

public enum WebOSError: LocalizedError {
    case connectionFailed(String)
    case notConnected
    case timeout
    case notPaired
    case pairingRejected
    case tvError(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail): return "Could not connect to the TV. \(detail)"
        case .notConnected: return "Not connected to the TV."
        case .timeout: return "The TV did not respond in time."
        case .notPaired: return "This TV isn't paired yet. Open the app and accept the prompt on the TV."
        case .pairingRejected: return "The pairing request was declined on the TV."
        case .tvError(let message): return "TV error: \(message)"
        }
    }
}

/// Runs an async operation with a hard timeout.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw WebOSError.timeout
        }
        guard let result = try await group.next() else { throw WebOSError.timeout }
        group.cancelAll()
        return result
    }
}

/// One WebSocket connection. LG TVs use a self-signed certificate on wss://:3001,
/// so the delegate accepts the server's certificate for this local connection.
final class WebSocketConnection: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!
    private let lock = NSLock()
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var closed = false

    var onText: (@Sendable (String) -> Void)?
    var onClose: (@Sendable (Error?) -> Void)?

    init(url: URL) {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
    }

    func connect(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            openContinuation = continuation
            lock.unlock()
            task.resume()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finishOpen(with: WebOSError.timeout)
            }
        }
        receiveNext()
    }

    private func finishOpen(with error: Error?) {
        lock.lock()
        let continuation = openContinuation
        openContinuation = nil
        lock.unlock()
        guard let continuation else { return }
        if let error {
            task.cancel()
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.onText?(text)
                }
                self.receiveNext()
            case .failure(let error):
                self.notifyClosed(error)
            }
        }
    }

    private func notifyClosed(_ error: Error?) {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        finishOpen(with: error ?? WebOSError.connectionFailed("Socket closed."))
        if !wasClosed {
            onClose?(error)
        }
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        finishOpen(with: nil)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        notifyClosed(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { notifyClosed(error) }
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The TV's certificate is self-signed; trust it for this direct local connection.
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// SSAP client for LG webOS TVs (2014+, including the C3).
///
/// Control channel: wss://tv:3001 (falls back to ws://tv:3000 for old firmware).
/// Button presses (arrows, OK, home, …) go over a second "pointer input" socket
/// the TV hands out via ssap://com.webos.service.networkinput/getPointerInputSocket.
public actor WebOSClient {
    public private(set) var isConnected = false

    private var control: WebSocketConnection?
    private var pointer: WebSocketConnection?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var registration: CheckedContinuation<String, Error>?
    private var registrationToken = UUID()
    private var requestCounter = 0
    private static let registerID = "register_0"

    public init() {}

    /// Connects and registers. Returns the client key (new if this was a first-time pairing —
    /// the user must accept the prompt shown on the TV within `pairingTimeout`).
    @discardableResult
    public func connect(host: String, clientKey: String?, pairingTimeout: TimeInterval = 60) async throws -> String {
        disconnect()
        let connection: WebSocketConnection
        do {
            connection = try await open(url: "wss://\(host):3001", timeout: 6)
        } catch {
            // Older firmware only listens on the plaintext port.
            connection = try await open(url: "ws://\(host):3000", timeout: 6)
        }
        connection.onText = { [weak self] text in
            Task { await self?.handleMessage(text) }
        }
        connection.onClose = { [weak self] _ in
            Task { await self?.connectionLost() }
        }
        control = connection

        let key = try await register(clientKey: clientKey, timeout: clientKey == nil ? pairingTimeout : 10)
        isConnected = true
        return key
    }

    public func disconnect() {
        isConnected = false
        control?.close()
        control = nil
        pointer?.close()
        pointer = nil
        failEverything(with: WebOSError.notConnected)
    }

    private func open(url urlString: String, timeout: TimeInterval) async throws -> WebSocketConnection {
        guard let url = URL(string: urlString) else { throw WebOSError.connectionFailed("Bad address.") }
        let connection = WebSocketConnection(url: url)
        try await connection.connect(timeout: timeout)
        return connection
    }

    private func connectionLost() {
        isConnected = false
        pointer?.close()
        pointer = nil
        control = nil
        failEverything(with: WebOSError.notConnected)
    }

    private func failEverything(with error: Error) {
        for (_, continuation) in pending { continuation.resume(throwing: error) }
        pending.removeAll()
        registration?.resume(throwing: error)
        registration = nil
    }

    // MARK: Registration / pairing

    private func register(clientKey: String?, timeout: TimeInterval) async throws -> String {
        guard let control else { throw WebOSError.notConnected }
        guard let manifestData = Self.manifestJSON.data(using: .utf8),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) else {
            throw WebOSError.tvError("Bad manifest.")
        }
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": manifest,
        ]
        if let clientKey { payload["client-key"] = clientKey }
        let message: [String: Any] = ["type": "register", "id": Self.registerID, "payload": payload]
        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(decoding: data, as: UTF8.self)

        let token = UUID()
        registrationToken = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.timeOutRegistration(token: token)
        }
        return try await withCheckedThrowingContinuation { continuation in
            registration = continuation
            Task {
                do { try await control.send(text) }
                catch { self.failRegistration(with: error, token: token) }
            }
        }
    }

    private func timeOutRegistration(token: UUID) {
        guard token == registrationToken, let continuation = registration else { return }
        registration = nil
        continuation.resume(throwing: WebOSError.timeout)
    }

    private func failRegistration(with error: Error, token: UUID) {
        guard token == registrationToken, let continuation = registration else { return }
        registration = nil
        continuation.resume(throwing: error)
    }

    // MARK: Requests

    @discardableResult
    public func request(_ uri: String, payload: [String: Any]? = nil, timeout: TimeInterval = 7) async throws -> [String: Any] {
        guard isConnected, let control else { throw WebOSError.notConnected }
        requestCounter += 1
        let id = "req_\(requestCounter)"
        var message: [String: Any] = ["type": "request", "id": id, "uri": uri]
        if let payload { message["payload"] = payload }
        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(decoding: data, as: UTF8.self)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.timeOutRequest(id: id)
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do { try await control.send(text) }
                catch { self.failRequest(id: id, error: error) }
            }
        }
    }

    private func timeOutRequest(id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: WebOSError.timeout)
    }

    private func failRequest(id: String, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    // MARK: Button (pointer input) socket

    /// Sends a remote-control button such as UP, DOWN, LEFT, RIGHT, ENTER, BACK, HOME, EXIT, MENU, 0–9.
    public func sendButton(_ button: String) async throws {
        if pointer == nil {
            try await openPointerSocket()
        }
        guard let pointer else { throw WebOSError.notConnected }
        do {
            try await pointer.send("type:button\nname:\(button)\n\n")
        } catch {
            self.pointer?.close()
            self.pointer = nil
            throw WebOSError.notConnected
        }
    }

    private func openPointerSocket() async throws {
        let payload = try await request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = payload["socketPath"] as? String, let url = URL(string: path) else {
            throw WebOSError.tvError("The TV did not provide a button input socket.")
        }
        let connection = WebSocketConnection(url: url)
        try await connection.connect(timeout: 6)
        connection.onClose = { [weak self] _ in
            Task { await self?.pointerClosed() }
        }
        pointer = connection
    }

    private func pointerClosed() {
        pointer = nil
    }

    // MARK: Incoming messages

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        let id = json["id"] as? String
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch type {
        case "registered":
            if let key = payload["client-key"] as? String, let continuation = registration {
                registration = nil
                continuation.resume(returning: key)
            }
        case "response":
            // The registration flow's intermediate PROMPT ack also arrives as a "response".
            if id == Self.registerID { return }
            if let id, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: payload)
            }
        case "error":
            let message = (json["error"] as? String) ?? "Unknown error"
            if id == Self.registerID, let continuation = registration {
                registration = nil
                let rejected = message.contains("403") || message.localizedCaseInsensitiveContains("cancel")
                continuation.resume(throwing: rejected ? WebOSError.pairingRejected : WebOSError.tvError(message))
            } else if let id, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(throwing: WebOSError.tvError(message))
            }
        default:
            break
        }
    }

    /// The standard registration manifest used by LG's own SDK tooling (same one every
    /// open-source webOS client library ships). The TV validates the signature blob as-is.
    private static let manifestJSON = """
    {
      "manifestVersion": 1,
      "appVersion": "1.1",
      "signed": {
        "created": "20140509",
        "appId": "com.lge.test",
        "vendorId": "com.lge",
        "localizedAppNames": {
          "": "LG Remote App",
          "ko-KR": "리모컨 앱",
          "zxx-XX": "ЛГ Rэмotэ AПП"
        },
        "localizedVendorNames": {
          "": "LG Electronics"
        },
        "permissions": [
          "TEST_SECURE",
          "CONTROL_INPUT_TEXT",
          "CONTROL_MOUSE_AND_KEYBOARD",
          "READ_INSTALLED_APPS",
          "READ_LGE_SDX",
          "READ_NOTIFICATIONS",
          "SEARCH",
          "WRITE_SETTINGS",
          "WRITE_NOTIFICATION_ALERT",
          "CONTROL_POWER",
          "READ_CURRENT_CHANNEL",
          "READ_RUNNING_APPS",
          "READ_UPDATE_INFO",
          "UPDATE_FROM_REMOTE_APP",
          "READ_LGE_TV_INPUT_EVENTS",
          "READ_TV_CURRENT_TIME"
        ],
        "serial": "2f930e2d2cfe083771f68e4fe7bb07"
      },
      "permissions": [
        "LAUNCH",
        "LAUNCH_WEBAPP",
        "APP_TO_APP",
        "CLOSE",
        "TEST_OPEN",
        "TEST_PROTECTED",
        "CONTROL_AUDIO",
        "CONTROL_DISPLAY",
        "CONTROL_INPUT_JOYSTICK",
        "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_INPUT_MEDIA_RECORDING",
        "CONTROL_INPUT_TEXT",
        "CONTROL_MOUSE_AND_KEYBOARD",
        "CONTROL_POWER",
        "READ_APP_STATUS",
        "READ_CURRENT_CHANNEL",
        "READ_INPUT_DEVICE_LIST",
        "READ_NETWORK_STATE",
        "READ_RUNNING_APPS",
        "READ_TV_CHANNEL_LIST",
        "WRITE_NOTIFICATION_TOAST",
        "READ_POWER_STATE",
        "READ_COUNTRY_INFO",
        "READ_SETTINGS",
        "CONTROL_TV_SCREEN",
        "CONTROL_TV_STANBY",
        "CONTROL_FAVORITE_GROUP",
        "CONTROL_USER_DEFINED",
        "UPDATE_FROM_REMOTE_APP",
        "READ_LGE_TV_INPUT_EVENTS",
        "READ_TV_CURRENT_TIME"
      ],
      "signatures": [
        {
          "signatureVersion": 1,
          "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
        }
      ]
    }
    """
}
