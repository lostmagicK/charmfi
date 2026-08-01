import Foundation
import Security
import AppAuth

final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()
    private init() {}

    private enum Key: String {
        case keycloakAuthState = "com.charmfi.keycloak.authstate"
        case googleAccessToken = "com.charmfi.google.accessToken"
        case googleRefreshToken = "com.charmfi.google.refreshToken"
        case googleTokenExpiry = "com.charmfi.google.tokenExpiry"
        case googleEmail = "com.charmfi.google.email"
    }

    // MARK: Keycloak

    func saveAuthState(_ state: OIDAuthState) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false) else { return }
        save(data: data, key: Key.keycloakAuthState.rawValue)
    }

    func loadAuthState() -> OIDAuthState? {
        guard let data = load(key: Key.keycloakAuthState.rawValue),
              let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { return nil }
        return state
    }

    func deleteAuthState() {
        delete(key: Key.keycloakAuthState.rawValue)
    }

    // MARK: Google

    func saveGoogleTokens(accessToken: String, refreshToken: String?, expiry: Date?, email: String?) {
        save(data: Data(accessToken.utf8), key: Key.googleAccessToken.rawValue)
        if let refreshToken {
            save(data: Data(refreshToken.utf8), key: Key.googleRefreshToken.rawValue)
        }
        if let expiry {
            let expiryStr = ISO8601DateFormatter().string(from: expiry)
            save(data: Data(expiryStr.utf8), key: Key.googleTokenExpiry.rawValue)
        }
        if let email {
            save(data: Data(email.utf8), key: Key.googleEmail.rawValue)
        }
    }

    func loadGoogleAccessToken() -> String? {
        load(key: Key.googleAccessToken.rawValue).flatMap { String(data: $0, encoding: .utf8) }
    }

    func loadGoogleEmail() -> String? {
        load(key: Key.googleEmail.rawValue).flatMap { String(data: $0, encoding: .utf8) }
    }

    func deleteGoogleTokens() {
        delete(key: Key.googleAccessToken.rawValue)
        delete(key: Key.googleRefreshToken.rawValue)
        delete(key: Key.googleTokenExpiry.rawValue)
        delete(key: Key.googleEmail.rawValue)
    }

    // MARK: Private Keychain helpers

    private func save(data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "in.charmee.charmfi"
        ]
        var updateAttrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "in.charmee.charmfi",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "in.charmee.charmfi"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
