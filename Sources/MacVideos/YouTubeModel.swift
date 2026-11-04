import AppKit
import Combine
import MacVideosCore

@MainActor final class YouTubeModel: ObservableObject {
    struct Grant: Codable { var email: String; var refreshToken: String }
    struct Pending: Codable { var account: String; var session: YouTubeUploadSession }
    @Published var clientID = ""
    @Published var clientSecret = ""
    @Published var account = ""
    @Published var message: String?
    @Published var working = false
    @Published var progress = 0.0
    @Published var video: YouTubeVideo?
    @Published var recent: [URL] = []
    @Published var links: [String: YouTubeVideo] = [:]
    @Published var pending: Pending?
    @Published var selected: URL?
    @Published var sheet: Sheet?
    enum Sheet: String, Identifiable { case setup, confirmation; var id: String { rawValue } }
    private let api = GoogleAPI()
    private let uploader = YouTubeUploader()
    private var grant: Grant?
    private var accessToken: String?
    private var expires = Date.distantPast
    private var task: Task<Void, Never>?
    private let defaults: UserDefaults
    private var client: GoogleClient { GoogleClient(id: clientID.trimmingCharacters(in: .whitespacesAndNewlines), secret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var configured: Bool { client.isValid }
    var preview = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let client = try YouTubeKeychain.read("client", as: GoogleClient.self) { clientID = client.id; clientSecret = client.secret }
            grant = try YouTubeKeychain.read("grant", as: Grant.self)
            account = grant?.email ?? ""
            pending = try YouTubeKeychain.read("pending", as: Pending.self)
        } catch { message = YouTubeKeychain.failure.localizedDescription }
        if let data = defaults.data(forKey: "youtubeLinks"), let value = try? JSONDecoder().decode([String: YouTubeVideo].self, from: data) {
            links = value.filter { YouTubeVideo.validID($0.value.id) }
        }
        recent = (defaults.stringArray(forKey: "recentRecordings") ?? []).map { URL(fileURLWithPath: $0) }
        // Explicit, offline-only layout fixture. Does not save preferences, sign in or upload.
        if ProcessInfo.processInfo.arguments.contains("--youtube-ui-preview") {
            preview = true
            recent = [URL(fileURLWithPath: "/tmp/mac-videos-layout-preview.mp4")]
        }
    }
    func remember(_ url: URL) {
        guard !preview else { return }
        recent.removeAll { $0 == url }; recent.insert(url, at: 0); recent = Array(recent.prefix(8))
        defaults.set(recent.map(\.path), forKey: "recentRecordings")
    }
    func open(_ url: URL) {
        if let video = links[url.path] { NSWorkspace.shared.open(video.watchURL); return }
        selected = url; video = nil; message = nil
        sheet = configured || preview ? .confirmation : .setup
    }
    func saveConfiguration() {
        guard !working, configured, grant == nil, pending == nil else { return }
        do {
            try YouTubeKeychain.write(client, account: "client")
            message = "Saved on this Mac. Return to your recording and sign in with Google."
        } catch { show(error) }
    }
    func signIn() {
        guard !working, configured, !preview else { return }
        working = true; message = "Finish signing in in your browser. No video is uploaded yet."
        task = Task {
            var receivedToken: String?
            do {
                try YouTubeKeychain.write(client, account: "client")
                let attempt = try OAuthAttempt()
                let loopback = GoogleLoopback()
                var redirect = ""
                let code = try await loopback.authorize(client: client, attempt: attempt) { redirect = $0 }
                try Task.checkCancellation()
                let tokens = try await api.exchange(code: code, attempt: attempt, redirect: redirect, client: client)
                receivedToken = tokens.refresh_token ?? tokens.access_token
                let email = try await api.account(accessToken: tokens.access_token)
                if let expected = pending?.account ?? grant?.email, expected != email {
                    throw YouTubeError.message("Choose the same Google account to resume. To change accounts, first check YouTube Studio, then Disconnect YouTube in Settings.")
                }
                guard let refresh = tokens.refresh_token, !refresh.isEmpty else { throw YouTubeError.expired }
                try Task.checkCancellation()
                let grant = Grant(email: email, refreshToken: refresh)
                try YouTubeKeychain.write(grant, account: "grant")
                self.grant = grant; account = email
                accessToken = tokens.access_token; expires = Date().addingTimeInterval(tokens.expires_in - 60)
                message = "Signed in. Review the details, then confirm Upload copy."
            } catch {
                if let receivedToken { try? await api.revoke(receivedToken) }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    message = "Sign-in cancelled. No video was uploaded."
                } else if error is URLError {
                    message = "The network connection failed. Reconnect and try Google sign-in again. No video was uploaded."
                } else { show(error) }
            }
            working = false; task = nil
        }
    }
    private func token() async throws -> String {
        if let accessToken, expires > Date() { return accessToken }
        guard var grant else { throw YouTubeError.expired }
        let tokens = try await api.refresh(grant.refreshToken, client: client)
        if let rotated = tokens.refresh_token {
            grant.refreshToken = rotated
            try YouTubeKeychain.write(grant, account: "grant"); self.grant = grant
        }
        accessToken = tokens.access_token; expires = Date().addingTimeInterval(tokens.expires_in - 60)
        return tokens.access_token
    }
    func upload(title: String, description: String, madeForKids: Bool) {
        guard !working, !preview, let file = selected, grant != nil else { return }
        if let pending, pending.session.file != file || pending.account != account {
            message = "Another upload is waiting. Close this sheet and retry that recording, or disconnect YouTube to forget its session after checking YouTube Studio."
            return
        }
        working = true; progress = 0; message = "Uploading a copy. Your MP4 stays on this Mac."
        task = Task {
            do {
                let token = try await token()
                try Task.checkCancellation()
                let session: YouTubeUploadSession
                if let pending { session = pending.session }
                else {
                    session = try await uploader.begin(file: file, title: title, description: description, madeForKids: madeForKids, token: token)
                    let pending = Pending(account: account, session: session)
                    // Keep in memory even if persistence fails: never create a duplicate on Retry.
                    self.pending = pending
                }
                if let pending { try YouTubeKeychain.write(pending, account: "pending") }
                try Task.checkCancellation()
                let result = try await uploader.upload(session, token: token) { self.progress = $0 }
                // Even if cancellation arrived alongside the successful response, remember this video.
                links[file.path] = result
                defaults.set(try JSONEncoder().encode(links), forKey: "youtubeLinks")
                video = result
                try YouTubeKeychain.delete("pending"); pending = nil
                message = "Uploaded as unlisted. YouTube may still be processing it; check playback before sharing."
            } catch { show(error) }
            working = false; task = nil
        }
    }
    func cancel() { task?.cancel() }
    func disconnect() {
        guard !working else { return }
        working = true
        task = Task {
            let saved = grant?.refreshToken
            do {
                try YouTubeKeychain.delete("grant"); grant = nil; account = ""; accessToken = nil; expires = .distantPast
                try YouTubeKeychain.delete("pending"); pending = nil
                if let saved { try await api.revoke(saved) }
                message = "Disconnected YouTube. Local videos and saved links stay on this Mac."
            } catch {
                message = grant == nil ? "Disconnected locally. If Google revocation failed, remove mac-videos from your Google Account permissions. If a resume item could not be removed, unlock Keychain and disconnect again." : YouTubeKeychain.failure.localizedDescription
            }
            working = false; task = nil
        }
    }
    private func show(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            message = "Cancelled. Bytes already sent may remain on YouTube. Retry continues this upload; your local video is safe."
        } else if error is URLError {
            message = "The network connection failed. Reconnect and Retry to continue the same upload. Your local video is safe."
        } else if let error = error as? YouTubeError { message = error.localizedDescription }
        else { message = "Could not complete this step. Check the local file and unlock your Keychain, then Retry. Your local video is safe." }
    }
    func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
