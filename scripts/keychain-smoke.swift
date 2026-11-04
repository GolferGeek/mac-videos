// Compile/run only as a signed, disposable executable. Never uses the app service.
import Foundation
import MacVideosCore

@main struct KeychainSmoke {
    @MainActor static func main() {
        let testService = "io.golfergeek.mac-videos.tests.smoke"
        do {
            if CommandLine.arguments.contains("--write") {
                try YouTubeKeychain.delete("fixture", service: testService)
                try YouTubeKeychain.write("synthetic-first", account: "fixture", service: testService)
                try YouTubeKeychain.write("synthetic-updated", account: "fixture", service: testService)
            }
            let value = try YouTubeKeychain.read("fixture", as: String.self, service: testService)
            guard value == "synthetic-updated" else { throw YouTubeKeychain.failure }
            if !CommandLine.arguments.contains("--write") {
                try YouTubeKeychain.delete("fixture", service: testService)
                let missing = try YouTubeKeychain.read("fixture", as: String.self, service: testService)
                guard missing == nil else { throw YouTubeKeychain.failure }
            }
            print("Keychain synthetic round trip: PASS")
        } catch {
            // Never emit an item or raw error payload.
            print("Keychain synthetic round trip: FAIL")
            exit(1)
        }
    }
}
