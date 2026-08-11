import Foundation
import UIKit
import Security

/// 应用侧稳定设备码。注意：不是苹果硬件 UDID（公开 API 无法读取）。
enum DeviceIdProvider {
    private static let prefsKey = "insulation_device_id"
    private static let keychainService = "com.baowen.insulation.device"
    private static let keychainAccount = "app_device_code"

    static func get() -> String {
        if let kc = keychainGet(), !kc.isEmpty {
            UserDefaults.standard.set(kc, forKey: prefsKey)
            return kc
        }
        if let legacy = UserDefaults.standard.string(forKey: prefsKey), !legacy.isEmpty {
            _ = keychainSet(legacy)
            return legacy
        }
        let vendor = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased() ?? "unknown"
        let uuid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        let deviceId = "ios_\(vendor)_\(uuid)"
        _ = keychainSet(deviceId)
        UserDefaults.standard.set(deviceId, forKey: prefsKey)
        return deviceId
    }

    /// 对外别名：网页可调用 getUDID；值为钥匙串稳定码，非硬件 UDID。
    static func udid() -> String { get() }

    static func vendorId() -> String {
        UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased() ?? ""
    }

    static func deviceLabel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        if identifier.isEmpty {
            return UIDevice.current.model
        }
        return "Apple \(identifier)"
    }

    private static func keychainGet() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func keychainSet(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
