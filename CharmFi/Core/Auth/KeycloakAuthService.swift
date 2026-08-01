import Foundation
import AppAuth
import UIKit

@MainActor
final class KeycloakAuthService {
    static let shared = KeycloakAuthService()
    private init() {}

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private let issuerURL = URL(string: "https://auth.charmee.in/realms/charmee")!
    private let clientID = "charmfi-web"
    private let redirectURI = URL(string: "charmfi://auth")!
    private let scopes = ["openid", "profile", "email", "offline_access"]

    func signIn(presenting viewController: UIViewController) async throws -> OIDAuthState {
        let config = try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL)

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: clientID,
            clientSecret: nil,
            scopes: scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            let flow = OIDAuthState.authState(byPresenting: request, presenting: viewController) { authState, error in
                if let authState {
                    nonisolated(unsafe) let s = authState
                    continuation.resume(returning: s)
                } else {
                    continuation.resume(throwing: error ?? AuthError.unknown)
                }
            }
            self.currentAuthorizationFlow = flow
        }
    }

    func restoreSession() -> OIDAuthState? {
        TokenStore.shared.loadAuthState()
    }

    func signOut() {
        TokenStore.shared.deleteAuthState()
    }

    func validAccessToken(from authState: OIDAuthState) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: error ?? AuthError.tokenRefreshFailed)
                }
            }
        }
    }
}

enum AuthError: Error, LocalizedError {
    case unknown
    case tokenRefreshFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .unknown: "Authentication failed."
        case .tokenRefreshFailed: "Could not refresh session. Please sign in again."
        case .notAuthenticated: "Not authenticated."
        }
    }
}
