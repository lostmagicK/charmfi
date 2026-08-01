import Foundation
import AppAuth
import UIKit

@Observable
@MainActor
final class AuthState {
    var isAuthenticated = false
    var userId: String?
    var displayName: String?
    var email: String?

    private(set) var authStateObj: OIDAuthState?

    func restoreSession() async {
        guard let stored = KeycloakAuthService.shared.restoreSession() else { return }
        do {
            let token = try await KeycloakAuthService.shared.validAccessToken(from: stored)
            if !token.isEmpty {
                authStateObj = stored
                extractClaims(from: stored)
                isAuthenticated = true
                TokenStore.shared.saveAuthState(stored)
            }
        } catch {
            isAuthenticated = false
        }
    }

    func signIn() async throws {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else {
            throw AuthError.unknown
        }
        let state = try await KeycloakAuthService.shared.signIn(presenting: vc)
        authStateObj = state
        extractClaims(from: state)
        TokenStore.shared.saveAuthState(state)
        isAuthenticated = true
    }

    func signOut() {
        KeycloakAuthService.shared.signOut()
        authStateObj = nil
        userId = nil
        displayName = nil
        email = nil
        isAuthenticated = false
    }

    func validAccessToken() async throws -> String {
        guard let state = authStateObj else { throw AuthError.notAuthenticated }
        let token = try await KeycloakAuthService.shared.validAccessToken(from: state)
        TokenStore.shared.saveAuthState(state)
        return token
    }

    private func extractClaims(from state: OIDAuthState) {
        guard let idToken = state.lastTokenResponse?.idToken,
              let payload = decodeJWTPayload(idToken) else { return }
        userId = payload["sub"] as? String
        displayName = payload["name"] as? String
        email = payload["email"] as? String
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
