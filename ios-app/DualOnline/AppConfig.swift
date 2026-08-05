import Foundation

enum AppConfig {
    static let appName = "双端随行录"
    static let bundleId = "com.dual.online"
    static let versionName = "1.0.0"
    static let versionCode = 10000
    static let serverBase = "https://example.com"
    static let assetsEntry = "index.html"
    static let splashDurationMs: Int = 3000

    static var insulationApiBase: String {
        let base = serverBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        if base.lowercased().hasSuffix("/api") { return base }
        return base + "/api"
    }

    static var gongtianApiBase: String {
        serverBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
