import Foundation

/// 编译期默认值。真实 API / 入口以 www/runtime-config.json 为准（打包时写入）。
enum AppConfig {
    static let appName = "保温系统"
    static let bundleId = "com.dual.online"
    static let versionName = "1.0.0"
    static let versionCode = 10000
    /// 留空：避免壳内写死地址覆盖打包配置；由 RuntimeConfig + config.remote.js 提供
    static let serverBase = ""
    static let assetsEntry = "baowen/shell.html"
    static let splashDurationMs: Int = 3000

    static var insulationApiBase: String { RuntimeConfig.shared.insulationApiBase }
    static var gongtianApiBase: String { RuntimeConfig.shared.gongtianApiBase }
}
