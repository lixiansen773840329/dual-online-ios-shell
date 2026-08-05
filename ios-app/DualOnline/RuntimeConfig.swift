import Foundation

/// 运行时配置：优先读打包写入的 www/runtime-config.json，
/// 这样 Windows 换 API 重打 IPA 无需重编原生壳。
final class RuntimeConfig {
    static let shared = RuntimeConfig()

    private(set) var serverBase: String = AppConfig.serverBase
    private(set) var assetsEntry: String = AppConfig.assetsEntry
    private(set) var appName: String = AppConfig.appName

    private init() {
        reload()
    }

    func reload() {
        serverBase = AppConfig.serverBase
        assetsEntry = AppConfig.assetsEntry
        appName = AppConfig.appName

        guard let url = Self.configURL(),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let s = obj["server_base"] as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // 空字符串也接受：表示不由原生注入 API，交给 config.remote.js
            serverBase = trimmed
        }
        if let e = obj["assets_entry"] as? String {
            let entry = e.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !entry.isEmpty {
                assetsEntry = entry
            }
        }
        if let n = obj["app_name"] as? String {
            let name = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                appName = name
            }
        }
    }

    var insulationApiBase: String {
        let base = serverBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        if base.lowercased().hasSuffix("/api") { return base }
        return base + "/api"
    }

    var gongtianApiBase: String {
        serverBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func configURL() -> URL? {
        if let url = Bundle.main.url(forResource: "runtime-config", withExtension: "json", subdirectory: "www"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let root = Bundle.main.resourceURL?.appendingPathComponent("www/runtime-config.json", isDirectory: false),
           FileManager.default.fileExists(atPath: root.path) {
            return root
        }
        // 开发态
        let dev = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("www/runtime-config.json", isDirectory: false)
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }
}
