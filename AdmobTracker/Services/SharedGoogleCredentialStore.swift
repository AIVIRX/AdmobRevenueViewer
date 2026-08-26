import Foundation
import GoogleSignIn
import Security

enum SharedGoogleCredentialStore {
    private static let accessGroup = "5C778DVBP3.com.Maicol.AdmobTracker.shared"
    private static let service = "com.Maicol.AdmobTracker.google-user"
    private static let account = "current"

    static func save(_ user: GIDGoogleUser) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: user, requiringSecureCoding: true)
        let lookup = baseQuery
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = lookup
            attributes.forEach { insert[$0] = $1 }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError(status: insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
