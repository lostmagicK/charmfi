import Foundation
@preconcurrency import GoogleSignIn
import UIKit

@MainActor
final class GmailAuthService {
    static let shared = GmailAuthService()
    private init() {}

    private let gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly"

    var isSignedIn: Bool { GIDSignIn.sharedInstance.currentUser != nil }
    var userEmail: String? { GIDSignIn.sharedInstance.currentUser?.profile?.email }

    func signIn(presenting viewController: UIViewController) async throws -> GIDGoogleUser {
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: [gmailReadonlyScope]
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    nonisolated(unsafe) let u = user
                    continuation.resume(returning: u)
                } else {
                    continuation.resume(throwing: GmailError.signInFailed)
                }
            }
        }
    }

    func refreshTokenIfNeeded() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw GmailError.notSignedIn }
        try await user.refreshTokensIfNeeded()
        return user.accessToken.tokenString
    }

    func restoreSession() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func hasScopeGranted() -> Bool {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return false }
        return user.grantedScopes?.contains(gmailReadonlyScope) ?? false
    }

    func addGmailScope(presenting viewController: UIViewController) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                continuation.resume(throwing: GmailError.notSignedIn)
                return
            }
            user.addScopes([gmailReadonlyScope], presenting: viewController) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

enum GmailError: LocalizedError {
    case notSignedIn
    case signInFailed
    case apiError(String)
    case noPatterns

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in to Gmail."
        case .signInFailed: "Google Sign-In failed."
        case .apiError(let msg): "Gmail API error: \(msg)"
        case .noPatterns: "No email patterns configured. Add patterns in Email Patterns first."
        }
    }
}
