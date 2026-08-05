import Foundation
import UIKit

enum DeviceIdProvider {
    private static let prefsKey = "insulation_device_id"
    private static let uuidKey = "insulation_app_uuid"

    static func get() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: prefsKey), !existing.isEmpty {
            return existing
        }
        let vendor = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased() ?? "unknown"
        var appUuid = defaults.string(forKey: uuidKey) ?? ""
        if appUuid.isEmpty {
            appUuid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
            defaults.set(appUuid, forKey: uuidKey)
        }
        let deviceId = "i_\(vendor)_\(appUuid)"
        defaults.set(deviceId, forKey: prefsKey)
        return deviceId
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
}
