import XCTest
import Security
import LocalAuthentication
@testable import MacVideosCore

@MainActor final class KeychainPolicyTests: XCTestCase {
    func testEveryAccountUsesSelectedBackendAndExplicitNamespace() {
        for account in ["client", "grant", "pending"] {
            let query = YouTubeKeychain.query(account, service: "io.golfergeek.mac-videos.tests.policy")
            XCTAssertEqual(query[kSecAttrService as String] as? String, "io.golfergeek.mac-videos.tests.policy")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, account)
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, YouTubeKeychain.usesDataProtection)
            if YouTubeKeychain.usesDataProtection {
                XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, YouTubeKeychain.accessGroup)
                XCTAssertTrue((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
            } else {
                XCTAssertNotEqual(YouTubeKeychain.service, "io.golfergeek.mac-videos.youtube")
                XCTAssertNil(query[kSecAttrAccessGroup as String])
            }
        }
    }
}
