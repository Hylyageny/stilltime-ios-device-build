import Foundation
import CryptoKit
import Security

enum ParentLock {
    private static let enabledKey = "parentPinEnabled.v1"
    private static let failCountKey = "parentPinFailCount.v1"
    private static let lockUntilKey = "parentPinLockUntil.v1"
    private static let keychainService = "com.stilltime.parentlock"
    private static let saltAccount = "parentPinSalt"
    private static let hashAccount = "parentPinHash"

    static var isEnabled: Bool {
        get { FocusStorage.shared?.bool(forKey: enabledKey) ?? false }
        set { FocusStorage.shared?.set(newValue, forKey: enabledKey) }
    }

    static var hasPin: Bool { keychainString(hashAccount) != nil }

    static func setPin(_ pin: String) -> Bool {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return false }
        let salt = generateSalt()
        keychainSet(saltAccount, salt)
        keychainSet(hashAccount, hashPin(salt: salt, pin: pin))
        isEnabled = true
        resetAttempts()
        return true
    }

    /// Seconds remaining before another PIN attempt is allowed; 0 if not locked out.
    static var lockRemainingSeconds: Int {
        let lockUntil = FocusStorage.shared?.double(forKey: lockUntilKey) ?? 0
        let remaining = lockUntil - Date().timeIntervalSince1970
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    static func verifyPin(_ pin: String) -> Bool {
        guard hasPin else { return true }
        guard lockRemainingSeconds == 0 else { return false }
        guard let salt = keychainString(saltAccount), let saved = keychainString(hashAccount) else { return false }
        let ok = hashPin(salt: salt, pin: pin) == saved
        if ok {
            resetAttempts()
        } else {
            let fails = (FocusStorage.shared?.integer(forKey: failCountKey) ?? 0) + 1
            FocusStorage.shared?.set(fails, forKey: failCountKey)
            let backoff = backoffSeconds(failCount: fails)
            if backoff > 0 {
                FocusStorage.shared?.set(Date().timeIntervalSince1970 + Double(backoff), forKey: lockUntilKey)
            }
        }
        return ok
    }

    static func removePin(currentPin: String) -> Bool {
        guard verifyPin(currentPin) else { return false }
        keychainDelete(saltAccount)
        keychainDelete(hashAccount)
        isEnabled = false
        resetAttempts()
        return true
    }

    private static func resetAttempts() {
        FocusStorage.shared?.set(0, forKey: failCountKey)
        FocusStorage.shared?.set(0.0, forKey: lockUntilKey)
    }

    // A 4-digit PIN is only 10,000 combinations; salting alone doesn't stop a live brute
    // force, so lock out with escalating backoff after 5 wrong attempts: 1s, 2s, 4s... capped
    // at 5 minutes.
    static func backoffSeconds(failCount: Int) -> Int {
        guard failCount >= 5 else { return 0 }
        return min(300, 1 << min(failCount - 5, 20))
    }

    // The salt is per-install, generated on first use and kept in the Keychain, not a
    // constant baked into the app, so a precomputed table for one install is useless
    // against another.
    private static func hashPin(salt: String, pin: String) -> String {
        let digest = SHA256.hash(data: Data("\(salt)::\(pin)".utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain (per-install secret storage; the extension never needs this, so it
    // isn't shared via the App Group's Keychain access group.)

    private static func keychainQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: account]
    }

    private static func keychainString(_ account: String) -> String? {
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainSet(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        let query = keychainQuery(account)
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func keychainDelete(_ account: String) {
        SecItemDelete(keychainQuery(account) as CFDictionary)
    }
}
