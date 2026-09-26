import Foundation
import Security

enum RemoteAuthenticationMode: String, Codable, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case password = "Username and Password"
    var id: String { rawValue }
}

struct SavedRemoteConnection: Codable {
    let address: String
    let username: String
    let authenticationMode: RemoteAuthenticationMode

    private static let settingsKey = "qBitX.remoteConnection"
    private static let keychainService = "life.andreacodin.qbitx"
    private static let keychainAccount = "remote-secret"

    static func load() -> SavedRemoteConnection? {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(SavedRemoteConnection.self, from: data)
    }

    static func secret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(secret: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
                throw ConnectionSettingsError.keychain
            }
        } else if status != errSecSuccess {
            throw ConnectionSettingsError.keychain
        }
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.settingsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func authentication(secret: String) -> APIAuthentication {
        switch authenticationMode {
        case .apiKey: .apiKey(secret)
        case .password: .password(username: username, password: secret)
        }
    }
}

enum ConnectionSettingsError: LocalizedError {
    case keychain
    case missingSecret

    var errorDescription: String? {
        switch self {
        case .keychain: "Could not save the Web UI credential in Keychain."
        case .missingSecret: "Enter an API key or password for this connection."
        }
    }
}
