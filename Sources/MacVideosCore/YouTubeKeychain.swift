import Foundation
import Security
import LocalAuthentication

// Synchronous calls on MainActor cannot overlap, including across Settings windows.
@MainActor public enum YouTubeKeychain {
    #if DATA_PROTECTION_KEYCHAIN
    public static let usesDataProtection = true
    public static let service = "io.golfergeek.mac-videos.youtube"
    #else
    public static let usesDataProtection = false
    // Isolated namespace: never query the legacy items that have stale ACLs.
    public static let service = "io.golfergeek.mac-videos.youtube.signed-v2"
    #endif
    public static let accessGroup = "227GEZ2676.io.golfergeek.mac-videos"

    static func query(_ account: String, service: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: usesDataProtection]
        if usesDataProtection {
            query[kSecAttrAccessGroup as String] = accessGroup
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    public static func read<T: Decodable>(_ account: String, as type: T.Type, service: String = service) throws -> T? {
        var query = query(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = try withoutInteraction { SecItemCopyMatching(query as CFDictionary, &item) }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = try? JSONDecoder().decode(type, from: data) else { throw failure }
        return value
    }

    public static func write<T: Encodable>(_ value: T, account: String, service: String = service) throws {
        let query = query(account, service: service)
        var attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value)]
        if usesDataProtection {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = try withoutInteraction {
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updated == errSecItemNotFound else { return updated }
            var addition = query.merging(attributes, uniquingKeysWith: { _, value in value })
            if !usesDataProtection {
                // Default file-Keychain ACLs can inherit password requirements. Explicitly
                // trust only this signed app; never use nil (which trusts every app).
                var app: SecTrustedApplication?
                guard SecTrustedApplicationCreateFromPath(Bundle.main.executablePath, &app) == errSecSuccess,
                      let app else { throw failure }
                var access: SecAccess?
                guard SecAccessCreate("mac-videos YouTube setup" as CFString, [app] as CFArray, &access) == errSecSuccess,
                      let access else { throw failure }
                addition[kSecAttrAccess as String] = access
            }
            return SecItemAdd(addition as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure }
    }

    public static func delete(_ account: String, service: String = service) throws {
        let status = try withoutInteraction { SecItemDelete(query(account, service: service) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure }
    }

    // The legacy SecItem adapter may ignore kSecUseAuthenticationUI. Suppress its
    // UI at the Keychain Services layer too, restoring the process setting on exit.
    // Every call in this app is synchronous and MainActor-isolated.
    private static func withoutInteraction<T>(_ operation: () throws -> T) throws -> T {
        if usesDataProtection { return try operation() }
        var allowed: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { throw failure }
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return try operation()
    }

    public static var failure: YouTubeError {
        .message("mac-videos could not access its protected YouTube setup. Unlock your Mac and try again. If this continues, check the app’s signing and Keychain access. Your local video is safe.")
    }
}
