import XCTest
@testable import MacVideosCore

private actor MockGoogle: YouTubeTransport {
    var responses: [Result<HTTPResult, Error>]
    var requests: [URLRequest] = []
    init(_ responses: [HTTPResult]) { self.responses = responses.map { .success($0) } }
    init(results: [Result<HTTPResult, Error>]) { responses = results }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !responses.isEmpty else { throw YouTubeError.message("Unexpected mock request") }
        return try responses.removeFirst().get()
    }
    func recorded() -> [URLRequest] { requests }
}

@MainActor final class YouTubeTests: XCTestCase {
    // These are deliberately artificial values, not Google-issued credentials.
    private let client = GoogleClient(id: "desktop.invalid", secret: "fixture-only")
    private let sessionURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=fixture")!
    private let success = HTTPResult(data: Data(#"{"id":"abcdefghijk","status":{"privacyStatus":"unlisted","embeddable":true,"uploadStatus":"uploaded"}}"#.utf8), status: 201)
    private func file(_ data: Data = Data(repeating: 7, count: 1024)) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-test-\(UUID()).mp4")
        try data.write(to: file); return file
    }
    private func session(_ file: URL) throws -> YouTubeUploadSession {
        let (size, date) = try YouTubeUploader.fingerprint(file)
        return .init(url: sessionURL, file: file, size: size, modified: date)
    }
    func testSavedLinkTitleIsOptionalAndLinksStayIdentical() throws {
        let old = try JSONDecoder().decode(YouTubeVideo.self, from: Data(#"{"id":"abcdefghijk"}"#.utf8))
        let titled = try JSONDecoder().decode(YouTubeVideo.self, from: Data(#"{"id":"abcdefghijk","title":"Walkthrough"}"#.utf8))
        XCTAssertNil(old.title)
        XCTAssertEqual(titled.title, "Walkthrough")
        XCTAssertEqual(old.watchURL, titled.watchURL)
        XCTAssertEqual(old.embedCode, titled.embedCode)
        XCTAssertEqual(try JSONDecoder().decode(YouTubeVideo.self, from: JSONEncoder().encode(titled)), titled)
    }
    func testUploadResponseRetainsOptionalTitle() async throws {
        let local = try file()
        defer { try? FileManager.default.removeItem(at: local) }
        let response = HTTPResult(data: Data(#"{"id":"abcdefghijk","snippet":{"title":"Walkthrough"},"status":{"privacyStatus":"unlisted","embeddable":true}}"#.utf8), status: 200)
        let transport = MockGoogle([response])
        let result = try await YouTubeUploader(transport: transport).upload(session(local), token: "fixture-only") { _ in }
        XCTAssertEqual(result.title, "Walkthrough")
        XCTAssertEqual(result.watchURL.absoluteString, "https://www.youtube.com/watch?v=abcdefghijk")
    }
    func testSetupSaveReopenAndClearUseMockStore() throws {
        let draft = GoogleClient(id: "offline-fixture.apps.googleusercontent.com", secret: "fixture-only")
        var stored: GoogleClient?
        var writes = 0
        var setup = YouTubeSetupState()
        XCTAssertFalse(setup.isSaved)
        try setup.save(GoogleClient(id: "   ")) { _ in XCTFail("Blank draft must not persist") }
        XCTAssertFalse(setup.isSaved)
        try setup.save(draft) { stored = $0; writes += 1 }
        XCTAssertTrue(setup.isSaved)
        try setup.save(draft) { _ in XCTFail("Repeated save must not overwrite") }
        XCTAssertEqual(writes, 1)
        var reopened = YouTubeSetupState(client: stored)
        XCTAssertTrue(reopened.isSaved)
        XCTAssertFalse(reopened.maskedClientID.contains("offline-fixture"))
        XCTAssertFalse(reopened.maskedClientID.contains(draft.id))
        XCTAssertFalse(reopened.maskedClientID.contains(draft.secret))
        try reopened.clear { stored = nil }
        XCTAssertFalse(reopened.isSaved)
        XCTAssertNil(stored)
        XCTAssertEqual(reopened.maskedClientID, "")
    }
    func testSetupPersistenceFailuresKeepPreviousState() throws {
        let draft = GoogleClient(id: "offline-fixture.apps.googleusercontent.com")
        var setup = YouTubeSetupState()
        XCTAssertThrowsError(try setup.save(draft) { _ in throw YouTubeError.unsafeResponse })
        XCTAssertFalse(setup.isSaved)
        try setup.save(draft) { _ in }
        XCTAssertThrowsError(try setup.clear { throw YouTubeError.unsafeResponse })
        XCTAssertTrue(setup.isSaved)
        XCTAssertEqual(setup.client?.id, draft.id)
        XCTAssertEqual(YouTubeSetupState(client: GoogleClient(id: "short")).maskedClientID, "••••••••")
    }
    func testPKCEKnownRFC7636VectorAndAuthorizationScope() throws {
        let attempt = OAuthAttempt(state: "expected", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(attempt.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let url = attempt.authorizationURL(client: client, redirect: "http://127.0.0.1:1234/oauth2callback")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "expected")
        let scope = items.first { $0.name == "scope" }!.value!
        XCTAssertTrue(scope.contains("youtube.upload")); XCTAssertFalse(scope.contains("youtube.readonly"))
        let random = try OAuthAttempt(); XCTAssertEqual(random.verifier.count, 43); XCTAssertNotEqual(random.state, random.verifier)
    }
    func testCallbacksRejectStateInjectionDuplicateFieldsAndWrongPath() throws {
        let attempt = OAuthAttempt(state: "expected", verifier: "fixture")
        XCTAssertEqual(try attempt.code(from: "/oauth2callback?code=hello%2Bworld&state=expected"), "hello+world")
        for target in ["/oauth2callback?code=abc&state=bad", "/oauth2callback?code=abc", "/oauth2callback?code=abc&state=expected&state=bad",
                       "/oauth2callback?code=a&code=b&state=expected", "/else?code=a&state=expected", "https://evil.invalid/oauth2callback?code=a&state=expected",
                       "//evil.invalid/oauth2callback?code=a&state=expected", "/oauth2callback?error=access_denied&state=expected"] {
            XCTAssertThrowsError(try attempt.code(from: target), target)
        }
    }
    func testExchangeRefreshIdentityAndRevocationUsePostBodies() async throws {
        let tokens = HTTPResult(data: Data(#"{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600}"#.utf8), status: 200)
        let mock = MockGoogle([tokens, tokens, .init(data: Data(#"{"email":"fixture@example.invalid","email_verified":true}"#.utf8), status: 200), .init(status: 200)])
        let api = GoogleAPI(transport: mock)
        let attempt = OAuthAttempt(state: "fixture", verifier: "verifier")
        _ = try await api.exchange(code: "code+&", attempt: attempt, redirect: "http://127.0.0.1:1234/oauth2callback", client: client)
        _ = try await api.refresh("fixture-refresh", client: client)
        let email = try await api.account(accessToken: "fixture-access")
        XCTAssertEqual(email, "fixture@example.invalid")
        try await api.revoke("fixture-refresh")
        let requests = await mock.recorded()
        XCTAssertEqual(requests[0].httpMethod, "POST")
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("code=code%2B%26")); XCTAssertTrue(body.contains("code_verifier=verifier"))
        XCTAssertFalse(requests[0].url!.absoluteString.contains("fixture"))
        XCTAssertTrue(String(data: requests[1].httpBody!, encoding: .utf8)!.contains("grant_type=refresh_token"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
        XCTAssertEqual(requests[3].url?.path, "/revoke")
        XCTAssertEqual(String(data: requests[3].httpBody!, encoding: .utf8), "token=fixture-refresh")
    }
    func testExpiredRefreshAndUnverifiedIdentityFailClosed() async throws {
        let api = GoogleAPI(transport: MockGoogle([.init(status: 400), .init(data: Data(#"{"email":"fixture@example.invalid","email_verified":false}"#.utf8), status: 200)]))
        do { _ = try await api.refresh("fixture", client: client); XCTFail() } catch { XCTAssertEqual(error as? YouTubeError, .expired) }
        do { _ = try await api.account(accessToken: "fixture"); XCTFail() } catch { XCTAssertEqual(error as? YouTubeError, .unsafeResponse) }
    }
    func testBeginSetsExplicitPrivacyEmbeddingAndAudience() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle([.init(status: 200, headers: ["Location": sessionURL.absoluteString])])
        let uploader = YouTubeUploader(transport: mock)
        _ = try await uploader.begin(file: file, title: "Walkthrough", description: "Optional", madeForKids: false, token: "fixture")
        let request = await mock.recorded()[0]
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let status = body["status"] as! [String: Any]
        XCTAssertEqual(status["privacyStatus"] as? String, "unlisted")
        XCTAssertEqual(status["embeddable"] as? Bool, true)
        XCTAssertEqual(status["selfDeclaredMadeForKids"] as? Bool, false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Content-Length"), "1024")
        XCTAssertTrue(request.url!.absoluteString.contains("notifySubscribers=false"))
    }
    func testUploadURLAllowlistRejectsCredentialExfiltration() {
        XCTAssertTrue(YouTubeUploader.allowedSessionURL(sessionURL))
        for text in ["http://www.googleapis.com/upload/youtube/v3/videos", "https://www.googleapis.com.evil.invalid/upload/youtube/v3/videos",
                     "https://127.0.0.1/upload/youtube/v3/videos", "https://www.googleapis.com:444/upload/youtube/v3/videos",
                     "https://user@www.googleapis.com/upload/youtube/v3/videos", "https://www.googleapis.com/other"] {
            XCTAssertFalse(YouTubeUploader.allowedSessionURL(URL(string: text)!))
        }
    }
    func testUntrustedSessionLocationDoesNotSendVideo() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle([.init(status: 200, headers: ["Location": "https://evil.invalid/upload"])])
        do {
            _ = try await YouTubeUploader(transport: mock).begin(file: file, title: "Test", description: "", madeForKids: false, token: "fixture")
            XCTFail()
        } catch { XCTAssertEqual(error as? YouTubeError, .unsafeResponse) }
        let requests = await mock.recorded(); XCTAssertEqual(requests.count, 1)
    }
    func testRetryQueriesSameSessionAndSendsOnlyMissingBytes() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle([.init(status: 308, headers: ["Range": "bytes=0-511"]), success])
        var progress: [Double] = []
        let video = try await YouTubeUploader(transport: mock).upload(session(file), token: "fixture") { progress.append($0) }
        XCTAssertEqual(video.id, "abcdefghijk"); XCTAssertEqual(progress.last, 1)
        let requests = await mock.recorded(); XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Range"), "bytes */1024")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Range"), "bytes 512-1023/1024")
        XCTAssertEqual(requests[1].httpBody?.count, 512)
        XCTAssertTrue(requests.allSatisfy { $0.url == sessionURL && $0.httpMethod == "PUT" })
    }
    func testLostFinalResponseRetryReturnsExistingVideoWithoutResending() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle(results: [.success(.init(status: 308)), .failure(URLError(.networkConnectionLost)), .success(success)])
        let uploader = YouTubeUploader(transport: mock); let session = try session(file)
        do { _ = try await uploader.upload(session, token: "fixture") { _ in }; XCTFail() } catch { XCTAssertTrue(error is URLError) }
        _ = try await uploader.upload(session, token: "fixture") { _ in }
        let requests = await mock.recorded(); XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Content-Range"), "bytes */1024")
    }
    func testChunksAreBoundedAndServerOffsetIsRespected() async throws {
        let file = try file(Data(repeating: 2, count: 8 * 1024 * 1024 + 17)); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle([.init(status: 308), .init(status: 308, headers: ["range": "bytes=0-8388607"]), success])
        _ = try await YouTubeUploader(transport: mock).upload(session(file), token: "fixture") { _ in }
        let requests = await mock.recorded()
        XCTAssertEqual(requests[1].httpBody?.count, 8 * 1024 * 1024)
        XCTAssertEqual(requests[2].httpBody?.count, 17)
    }
    func testChangedFileAndInvalidRangeFailWithoutUploading() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let saved = try session(file); try Data([1, 2, 3]).write(to: file)
        let mock = MockGoogle([])
        do { _ = try await YouTubeUploader(transport: mock).upload(saved, token: "fixture") { _ in }; XCTFail() } catch { }
        let requests = await mock.recorded(); XCTAssertTrue(requests.isEmpty)
        let bad = MockGoogle([.init(status: 308, headers: ["range": "bytes=0-99999999"])])
        do { _ = try await YouTubeUploader(transport: bad).upload(session(file), token: "fixture") { _ in }; XCTFail() } catch { XCTAssertEqual(error as? YouTubeError, .unsafeResponse) }
    }
    func testFinalPrivacyAndEmbedMustBeConfirmed() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        for json in [#"{"id":"abcdefghijk","status":{"privacyStatus":"public","embeddable":true}}"#,
                     #"{"id":"abcdefghijk","status":{"privacyStatus":"unlisted","embeddable":false}}"#,
                     #"{"id":"bad<script>","status":{"privacyStatus":"unlisted","embeddable":true}}"#] {
            let mock = MockGoogle([.init(data: Data(json.utf8), status: 200)])
            do { _ = try await YouTubeUploader(transport: mock).upload(session(file), token: "fixture") { _ in }; XCTFail() } catch { XCTAssertTrue(error is YouTubeError) }
        }
    }
    func testFriendlyQuotaChannelExpiredAndMissingSessionErrors() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        for (status, body, expected) in [(403, "quotaExceeded", "quota"), (403, "youtubeSignupRequired", "channel"), (401, "", "expired"), (404, "", "Studio")] {
            let mock = MockGoogle([.init(data: Data(body.utf8), status: status)])
            do { _ = try await YouTubeUploader(transport: mock).upload(session(file), token: "fixture") { _ in }; XCTFail() }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected)) }
        }
    }
    func testCancellationStopsBeforeMediaChunkAndLeavesFile() async throws {
        let file = try file(); defer { try? FileManager.default.removeItem(at: file) }
        let mock = MockGoogle([.init(status: 308)])
        let session = try session(file)
        let task = Task { try await YouTubeUploader(transport: mock).upload(session, token: "fixture") { _ in } }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await mock.recorded(); XCTAssertTrue(requests.allSatisfy { $0.httpBody?.isEmpty == true })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
