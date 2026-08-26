import Foundation
@preconcurrency import GoogleSignIn

struct AuthUserProfile: Hashable {
    let email: String
    let displayName: String
    let photoURL: URL?
}

protocol AuthManaging {
    var currentUser: AuthUserProfile? { get }
    func restorePreviousSignIn() async
    func signIn() async throws -> AuthUserProfile
    func signOut() async
    func accessToken() async throws -> String
}

@MainActor
final class AuthManager: AuthManaging {
    private var googleUser: GIDGoogleUser?

    var currentUser: AuthUserProfile? {
        guard let googleUser else { return nil }
        return AuthUserProfile(
            email: googleUser.profile?.email ?? "",
            displayName: googleUser.profile?.name ?? "",
            photoURL: googleUser.profile?.imageURL(withDimension: 200)
        )
    }

    func restorePreviousSignIn() async {
        do {
            try configureSignInIfNeeded()
        } catch {
            return
        }
        googleUser = await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user)
            }
        } ?? GIDSignIn.sharedInstance.currentUser
        if let googleUser {
            try? SharedGoogleCredentialStore.save(googleUser)
        }
    }

    func signIn() async throws -> AuthUserProfile {
        try configureSignInIfNeeded()
        guard let presenter = GoogleSignInHelper.topViewController() else {
            throw AuthManagerError.missingPresenter
        }

        let user = try await signIn(with: presenter)
        googleUser = user
        try? SharedGoogleCredentialStore.save(user)
        guard let profile = currentUser else {
            throw AuthManagerError.missingProfile
        }
        return profile
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        SharedGoogleCredentialStore.remove()
        googleUser = nil
    }

    func accessToken() async throws -> String {
        try configureSignInIfNeeded()
        guard let user = googleUser ?? GIDSignIn.sharedInstance.currentUser else {
            throw AuthManagerError.missingUser
        }

        let refreshedUser = try await refreshTokensIfNeeded(for: user)
        googleUser = refreshedUser
        try? SharedGoogleCredentialStore.save(refreshedUser)

        let token = refreshedUser.accessToken.tokenString
        if token.isEmpty {
            throw AuthManagerError.missingToken
        }
        return token
    }

    @discardableResult
    private func configureSignInIfNeeded() throws -> Bool {
        guard GIDSignIn.sharedInstance.configuration == nil else { return false }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw AuthManagerError.missingClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        return true
    }

    private func signIn(with presenter: UIViewController) async throws -> GIDGoogleUser {
        let additionalScopes = [
            "https://www.googleapis.com/auth/admob.readonly",
            "https://www.googleapis.com/auth/adsense.readonly"
        ]

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: additionalScopes) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user = result?.user else {
                    continuation.resume(throwing: AuthManagerError.missingUser)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    private func refreshTokensIfNeeded(for user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: refreshedUser ?? user)
            }
        }
    }
}

enum AuthManagerError: Error {
    case missingPresenter
    case missingUser
    case missingProfile
    case missingToken
    case missingClientID
}

extension AuthManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingPresenter:
            return "Unable to present Google Sign-In."
        case .missingUser:
            return "Google Sign-In did not return a user."
        case .missingProfile:
            return "Google Sign-In profile data is missing."
        case .missingToken:
            return "Google access token is missing. Check OAuth client configuration and scopes."
        case .missingClientID:
            return "Missing GIDClientID in Info.plist."
        }
    }
}
