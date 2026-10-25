import ConclaveCore
import Foundation
import Security

/// The paired device in the Keychain. The token is the key to the person's decks, so it never goes
/// into a plain file or UserDefaults; "this device only" keeps it out of backups restored onto
/// another phone (that phone pairs itself), "after first unlock" lets the app refresh in the background.
struct KeychainDeviceStore: DeviceStore {
    /// One item, found by service and account. A computed property: a `[String: Any]` isn't Sendable.
    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.conclave.mobile.device",
            kSecAttrAccount as String: "device",
        ]
    }

    func load() -> Device? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(Device.self, from: data)
    }

    func save(_ device: Device) throws {
        SecItemDelete(item as CFDictionary)
        var query = item
        query[kSecValueData as String] = try JSONEncoder().encode(device)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func clear() {
        SecItemDelete(item as CFDictionary)
    }
}

struct KeychainError: Error {
    let status: OSStatus
}
