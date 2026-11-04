import AppKit
import Network
import Security
import MacVideosCore

// Refresh token, client configuration and resumable URL never enter preferences or logs.
enum YouTubeKeychain {
    private static let service = "io.golfergeek.mac-videos.youtube"
    static func read<T: Decodable>(_ account: String, as type: T.Type) throws -> T? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw failure }
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw failure }
        return value
    }
    static func write<T: Encodable>(_ value: T, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, value in value }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure }
    }
    static func delete(_ account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure }
    }
    static var failure: YouTubeError { .message("mac-videos could not access its YouTube Keychain item. Unlock your login Keychain and try again.") }
}

@MainActor final class GoogleLoopback {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?

    func authorize(client: GoogleClient, attempt: OAuthAttempt, opened: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(.failure(CancellationError())); return }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        Task { @MainActor in
                            guard let self, self.continuation != nil else { return }
                            switch state {
                            case .ready:
                                guard let port = self.listener?.port else { self.finish(.failure(YouTubeError.unsafeResponse)); return }
                                let redirect = "http://127.0.0.1:\(port.rawValue)/oauth2callback"
                                opened(redirect)
                                guard NSWorkspace.shared.open(attempt.authorizationURL(client: client, redirect: redirect)) else {
                                    self.finish(.failure(YouTubeError.message("Could not open your browser. Please try sign-in again."))); return
                                }
                            case .failed:
                                self.finish(.failure(YouTubeError.message("Could not start Google sign-in on this Mac. Please try again.")))
                            default: break
                            }
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in
                            guard let self, self.continuation != nil, self.connections.count < 8 else { connection.cancel(); return }
                            self.connections.append(connection)
                            connection.start(queue: .main)
                            self.receive(connection, data: Data(), attempt: attempt)
                        }
                    }
                    listener.start(queue: .main)
                    timeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(180))
                        guard !Task.isCancelled else { return }
                        self?.finish(.failure(YouTubeError.message("Google sign-in timed out. Please try again.")))
                    }
                } catch { finish(.failure(YouTubeError.message("Could not start Google sign-in. Please try again."))) }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func receive(_ connection: NWConnection, data: Data, attempt: OAuthAttempt) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { connection.cancel(); return }
                var received = data; received.append(bytes ?? Data())
                guard received.count <= 8192 else { connection.cancel(); return }
                if let text = String(data: received, encoding: .utf8), text.contains("\r\n\r\n") {
                    let line = text.components(separatedBy: "\r\n")[0].components(separatedBy: " ")
                    guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/oauth2callback?") else { connection.cancel(); return }
                    let result = Result { try attempt.code(from: line[1]) }
                    let message = (try? result.get()) != nil ? "Sign-in received. Return to mac-videos." : "Sign-in could not be verified. Return to mac-videos and try again."
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(message.utf8.count)\r\n\r\n\(message)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    self.connections.removeAll { $0 === connection }
                    self.finish(result)
                } else if complete || error != nil { connection.cancel() }
                else { self.receive(connection, data: received, attempt: attempt) }
            }
        }
    }
    private func finish(_ result: Result<String, Error>) {
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        // The small browser response has already been queued. Close remaining sockets promptly.
        for connection in connections { connection.cancel() }; connections.removeAll()
        let waiting = continuation; continuation = nil; waiting?.resume(with: result)
    }
}
