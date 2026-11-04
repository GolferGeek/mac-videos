import XCTest
import MacVideosCore

@MainActor final class YouTubeCredentialLoadingTests: XCTestCase {
    func testRecentRecordingsSortByCreationAndPreserveLinksOnRemember() throws {
        let suite = "mac-videos.tests.recent.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let older = folder.appendingPathComponent("older.mp4")
        let newer = folder.appendingPathComponent("newer.mp4")
        try Data([0]).write(to: older); try Data([0]).write(to: newer)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: newer.path)
        let links = Data(#"{"/missing.mp4":{"id":"abcdefghijk"}}"#.utf8)
        defaults.set(links, forKey: "youtubeLinks")
        var reads = 0
        let model = YouTubeModel(defaults: defaults) { reads += 1; return .init() }
        model.remember(newer); model.remember(older); model.remember(older)
        XCTAssertEqual(model.sortedRecordings, [newer, older])
        XCTAssertEqual(model.recent.count, 2)
        XCTAssertEqual(defaults.data(forKey: "youtubeLinks"), links)
        let reopened = YouTubeModel(defaults: defaults) { reads += 1; return .init() }
        XCTAssertEqual(reopened.sortedRecordings, [newer, older])
        XCTAssertEqual(reopened.links["/missing.mp4"]?.id, "abcdefghijk")
        XCTAssertEqual(reads, 0)
    }
    func testLaunchDoesNotReadAndExplicitEntryLoadsOnlyOnce() {
        var reads = 0
        let model = YouTubeModel(defaults: UserDefaults(suiteName: "mac-videos.tests.lazy")!) {
            reads += 1
            return .init(client: GoogleClient(id: "offline-fixture.apps.googleusercontent.com"), grant: nil, pending: nil)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertFalse(model.configured)
        model.loadCredentials()
        model.loadCredentials()
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(model.configured)
    }

    func testFailureDoesNotEnableOverwriteAndExplicitRetryCanRecover() {
        var reads = 0
        let model = YouTubeModel(defaults: UserDefaults(suiteName: "mac-videos.tests.lazy")!) {
            reads += 1
            if reads == 1 { throw YouTubeKeychain.failure }
            return .init(client: nil, grant: nil, pending: nil)
        }
        model.clientID = "offline-fixture.apps.googleusercontent.com"
        XCTAssertFalse(model.canSaveSetup)
        model.loadCredentials()
        XCTAssertFalse(model.canSaveSetup)
        XCTAssertNotNil(model.message)
        model.loadCredentials()
        XCTAssertEqual(reads, 2)
        XCTAssertTrue(model.canSaveSetup)
        XCTAssertNil(model.message)
    }

    func testUploadPreparationLoadsBeforeChoosingSheet() {
        var reads = 0
        let model = YouTubeModel(defaults: UserDefaults(suiteName: "mac-videos.tests.lazy")!) {
            reads += 1
            return .init(client: GoogleClient(id: "offline-fixture.apps.googleusercontent.com"), grant: nil, pending: nil)
        }
        model.open(URL(fileURLWithPath: "/tmp/synthetic-upload.mp4"))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(model.sheet, .confirmation)
    }
}
