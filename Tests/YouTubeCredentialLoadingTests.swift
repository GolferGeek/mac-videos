import XCTest
import MacVideosCore

@MainActor final class YouTubeCredentialLoadingTests: XCTestCase {
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
