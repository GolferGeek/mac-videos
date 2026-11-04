import Foundation
import CryptoKit
import Security

public enum YouTubeError: LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    public static let expired = Self.message("Your Google sign-in expired. Click Sign in again to continue this upload.")
    public static let unsafeResponse = Self.message("YouTube returned an unexpected response. Your local video is safe.")
}

public struct HTTPResult: Sendable {
    public var data: Data
    public var status: Int
    public var headers: [String: String]
    public init(data: Data = Data(), status: Int, headers: [String: String] = [:]) {
        self.data = data; self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
    }
}

public protocol YouTubeTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

// No redirects: never forward bearer credentials or recording bytes to a redirected host.
public final class GoogleTransport: NSObject, YouTubeTransport, URLSessionTaskDelegate, @unchecked Sendable {
    public override init() { super.init() }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeError.unsafeResponse }
        return HTTPResult(data: data, status: http.statusCode, headers: http.allHeaderFields.reduce(into: [:]) {
            if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value }
        })
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GoogleClient: Codable, Sendable {
    public var id: String
    public var secret: String
    public init(id: String, secret: String = "") { self.id = id; self.secret = secret }
    public var isValid: Bool {
        id.hasSuffix(".apps.googleusercontent.com") && !id.contains(where: { $0.isWhitespace }) && id.count < 300
    }
}

public struct OAuthAttempt: Sendable {
    public let state: String
    public let verifier: String
    public init() throws { state = try Self.random(); verifier = try Self.random() }
    public init(state: String, verifier: String) { self.state = state; self.verifier = verifier }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw YouTubeError.unsafeResponse }
        return encode(Data(bytes))
    }
    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public var challenge: String { Self.encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public func authorizationURL(client: GoogleClient, redirect: String) -> URL {
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": client.id, "redirect_uri": redirect, "response_type": "code",
                          "scope": "https://www.googleapis.com/auth/youtube.upload openid email",
                          "access_type": "offline", "prompt": "consent select_account", "state": state,
                          "code_challenge": challenge, "code_challenge_method": "S256"].map(URLQueryItem.init)
        return url.url!
    }
    public func code(from target: String) throws -> String {
        guard let parts = URLComponents(string: target), parts.scheme == nil, parts.host == nil, parts.path == "/oauth2callback", parts.fragment == nil,
              let items = parts.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else {
            throw YouTubeError.message("Google sign-in could not be verified. Please try again.")
        }
        if items.contains(where: { $0.name == "error" }) { throw YouTubeError.message("Google sign-in was cancelled or denied.") }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw YouTubeError.unsafeResponse }
        return code
    }
}

public struct GoogleTokens: Codable, Sendable {
    public let access_token: String
    public let refresh_token: String?
    public let expires_in: Double
}

@MainActor public final class GoogleAPI {
    private let transport: any YouTubeTransport
    public init(transport: any YouTubeTransport = GoogleTransport()) { self.transport = transport }
    public static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    private func token(_ values: [String: String], client: GoogleClient) async throws -> GoogleTokens {
        var fields = values; fields["client_id"] = client.id
        if !client.secret.isEmpty { fields["client_secret"] = client.secret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.httpBody = Self.form(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let result = try await transport.send(request)
        guard result.status == 200 else { throw YouTubeError.expired }
        guard let tokens = try? JSONDecoder().decode(GoogleTokens.self, from: result.data), !tokens.access_token.isEmpty else { throw YouTubeError.unsafeResponse }
        return tokens
    }
    public func exchange(code: String, attempt: OAuthAttempt, redirect: String, client: GoogleClient) async throws -> GoogleTokens {
        try await token(["grant_type": "authorization_code", "code": code, "code_verifier": attempt.verifier, "redirect_uri": redirect], client: client)
    }
    public func refresh(_ refreshToken: String, client: GoogleClient) async throws -> GoogleTokens {
        try await token(["grant_type": "refresh_token", "refresh_token": refreshToken], client: client)
    }
    public func account(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let result = try await transport.send(request)
        struct Identity: Decodable { let email: String; let email_verified: Bool }
        guard result.status == 200, let identity = try? JSONDecoder().decode(Identity.self, from: result.data), identity.email_verified else { throw YouTubeError.unsafeResponse }
        return identity.email
    }
    public func revoke(_ token: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"; request.httpBody = Self.form(["token": token])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let result = try await transport.send(request)
        guard result.status == 200 else { throw YouTubeError.message("Disconnected on this Mac. Google could not be reached to revoke access. Remove mac-videos access in your Google Account permissions too.") }
    }
}

public struct YouTubeVideo: Codable, Sendable, Equatable {
    public let id: String
    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    public var embedCode: String { "<iframe width=\"560\" height=\"315\" src=\"https://www.youtube.com/embed/\(id)\" title=\"YouTube video player\" frameborder=\"0\" allowfullscreen></iframe>" }
    public static func validID(_ id: String) -> Bool {
        id.count == 11 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0) }
    }
}

public struct YouTubeUploadSession: Codable, Sendable {
    public let url: URL
    public let file: URL
    public let size: UInt64
    public let modified: Date
    public init(url: URL, file: URL, size: UInt64, modified: Date) { self.url = url; self.file = file; self.size = size; self.modified = modified }
}

@MainActor public final class YouTubeUploader {
    private let transport: any YouTubeTransport
    public init(transport: any YouTubeTransport = GoogleTransport()) { self.transport = transport }
    public static func allowedSessionURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "www.googleapis.com" && (url.port == nil || url.port == 443) &&
        url.user == nil && url.password == nil && url.fragment == nil && url.path == "/upload/youtube/v3/videos"
    }
    public static func fingerprint(_ file: URL) throws -> (UInt64, Date) {
        // URL.resourceValues can cache old size/date values on the same URL instance.
        // Read fresh filesystem attributes before every attempt and every chunk.
        let values = try FileManager.default.attributesOfItem(atPath: file.path)
        guard file.isFileURL, file.pathExtension.lowercased() == "mp4", values[.type] as? FileAttributeType == .typeRegular,
              let size = values[.size] as? NSNumber, size.uint64Value > 0, let date = values[.modificationDate] as? Date else {
            throw YouTubeError.message("Choose a saved MP4 recording that is still on this Mac.")
        }
        return (size.uint64Value, date)
    }
    private func request(_ url: URL, token: String, method: String = "PUT") -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    public func begin(file: URL, title: String, description: String, madeForKids: Bool, token: String) async throws -> YouTubeUploadSession {
        let (size, date) = try Self.fingerprint(file)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 100,
              !title.contains("<"), !title.contains(">"), description.utf8.count <= 5000 else {
            throw YouTubeError.message("Use a title of 1–100 bytes without < or >, and a description under 5,000 bytes.")
        }
        var request = request(URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers=false")!, token: token, method: "POST")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["snippet": ["title": title, "description": description],
            "status": ["privacyStatus": "unlisted", "embeddable": true, "selfDeclaredMadeForKids": madeForKids]])
        let result = try await transport.send(request)
        try Self.check(result)
        guard result.status == 200, let location = result.headers["location"], let url = URL(string: location), Self.allowedSessionURL(url) else { throw YouTubeError.unsafeResponse }
        return YouTubeUploadSession(url: url, file: file, size: size, modified: date)
    }
    // Query first on every attempt: handles a lost final response without creating another video.
    public func upload(_ session: YouTubeUploadSession, token: String, progress: (Double) -> Void) async throws -> YouTubeVideo {
        try Task.checkCancellation()
        guard Self.allowedSessionURL(session.url) else { throw YouTubeError.unsafeResponse }
        let (size, date) = try Self.fingerprint(session.file)
        guard size == session.size, date == session.modified else { throw YouTubeError.message("This MP4 changed since the upload started. Retry with the original file; no new upload was created.") }
        var query = request(session.url, token: token)
        query.setValue("bytes */\(size)", forHTTPHeaderField: "Content-Range"); query.httpBody = Data()
        var result = try await transport.send(query)
        try Self.check(result)
        if result.status == 200 || result.status == 201 { return try Self.video(result) }
        var offset = try Self.offset(result, size: size)
        let handle = try FileHandle(forReadingFrom: session.file)
        defer { try? handle.close() }
        while offset < size {
            try Task.checkCancellation()
            progress(Double(offset) / Double(size))
            let current = try Self.fingerprint(session.file)
            guard current.0 == size, current.1 == date else { throw YouTubeError.message("The recording changed during upload. Stop and check the original MP4 before retrying.") }
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(min(8 * 1024 * 1024, size - offset))), !data.isEmpty else { throw YouTubeError.unsafeResponse }
            var chunk = request(session.url, token: token)
            chunk.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            chunk.setValue("bytes \(offset)-\(offset + UInt64(data.count) - 1)/\(size)", forHTTPHeaderField: "Content-Range")
            chunk.httpBody = data
            result = try await transport.send(chunk)
            try Self.check(result)
            if result.status == 200 || result.status == 201 { progress(1); return try Self.video(result) }
            let next = try Self.offset(result, size: size)
            guard next > offset, next <= offset + UInt64(data.count) else { throw YouTubeError.unsafeResponse }
            offset = next
        }
        throw YouTubeError.message("YouTube has all the bytes but has not confirmed the video yet. Retry to check this same upload.")
    }
    private static func offset(_ result: HTTPResult, size: UInt64) throws -> UInt64 {
        guard result.status == 308 else { throw YouTubeError.unsafeResponse }
        guard let range = result.headers["range"] else { return 0 }
        guard range.hasPrefix("bytes=0-"), let last = UInt64(range.dropFirst(8)), last < size else { throw YouTubeError.unsafeResponse }
        return last + 1
    }
    private static func video(_ result: HTTPResult) throws -> YouTubeVideo {
        struct Response: Decodable {
            struct Status: Decodable { let privacyStatus: String; let embeddable: Bool; let uploadStatus: String? }
            let id: String; let status: Status
        }
        guard let video = try? JSONDecoder().decode(Response.self, from: result.data), YouTubeVideo.validID(video.id) else { throw YouTubeError.unsafeResponse }
        guard video.status.privacyStatus == "unlisted", video.status.embeddable,
              video.status.uploadStatus != "rejected", video.status.uploadStatus != "failed", video.status.uploadStatus != "deleted" else {
            throw YouTubeError.message("YouTube received the video but did not confirm unlisted and embeddable status. Check YouTube Studio before sharing; Retry checks this upload again.")
        }
        return YouTubeVideo(id: video.id)
    }
    private static func check(_ result: HTTPResult) throws {
        if result.status == 401 { throw YouTubeError.expired }
        if result.status == 404 || result.status == 410 { throw YouTubeError.message("This upload session expired. Check YouTube Studio for the video before starting another upload.") }
        guard result.status == 200 || result.status == 201 || result.status == 308 else {
            // Inspect known reasons only; never display raw responses/session URLs/tokens.
            let body = String(data: result.data, encoding: .utf8) ?? ""
            if body.contains("quotaExceeded") || body.contains("uploadLimitExceeded") || body.contains("dailyLimitExceeded") {
                throw YouTubeError.message("Your YouTube upload quota is used up. Try again after it resets.")
            }
            if body.contains("youtubeSignupRequired") || body.contains("channelNotFound") {
                throw YouTubeError.message("This Google account needs a YouTube channel. Create one on youtube.com, then sign in again.")
            }
            throw YouTubeError.message("YouTube could not finish this request. Check your Google setup and connection, then Retry. Your local video is safe.")
        }
    }
}
