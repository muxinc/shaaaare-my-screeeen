import Foundation
import Security

class CredentialStore {
    private let service = "com.mux.shaaaare-my-screeeen"
    private let tokenIdKey = "mux-token-id"
    private let tokenSecretKey = "mux-token-secret"

    func saveCredentials(tokenId: String, tokenSecret: String) -> Bool {
        let savedId = save(key: tokenIdKey, value: tokenId)
        let savedSecret = save(key: tokenSecretKey, value: tokenSecret)
        return savedId && savedSecret
    }

    func getCredentials() -> (tokenId: String, tokenSecret: String)? {
        guard let tokenId = read(key: tokenIdKey),
              let tokenSecret = read(key: tokenSecretKey) else {
            return nil
        }
        return (tokenId, tokenSecret)
    }

    func hasCredentials() -> Bool {
        return containsItem(key: tokenIdKey) && containsItem(key: tokenSecretKey)
    }

    func deleteCredentials() {
        delete(key: tokenIdKey)
        delete(key: tokenSecretKey)
    }

    // MARK: - Keychain Operations

    private func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            appLog("[CredentialStore] Save failed for \(key): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    private func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func containsItem(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
