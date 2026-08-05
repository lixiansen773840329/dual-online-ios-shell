import UIKit
import WebKit

final class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let bridge = NativeBridge()
    private var splashView: UIView!
    private var countdownLabel: UILabel!
    private var splashFinished = false
    private var splashTimer: Timer?
    private var contentProtectionEnabled = false
    private var statusBarStyle: UIStatusBarStyle = .lightContent
    private var payPageReadyAt: TimeInterval = 0
    private var lastUserGestureAt: TimeInterval = 0
    private var userArmedPayLaunch = false

    private let protectedTabs: Set<String> = ["duct-nail", "irregular-duct-nail"]

    var safeAreaTop: CGFloat { view.safeAreaInsets.top }
    var safeAreaBottom: CGFloat { view.safeAreaInsets.bottom }

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.01, blue: 0.01, alpha: 1)
        bridge.controller = self
        setupWebView()
        setupSplash()
        loadStartPage()
        startSplashCountdown()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let ucc = config.userContentController
        let deviceId = DeviceIdProvider.get()
        let flags = NativeBridge.injectAppFlagsJavaScript(
            deviceId: deviceId,
            insulationApi: AppConfig.insulationApiBase,
            gongtianApi: AppConfig.gongtianApiBase
        )
        let bridgeJs = NativeBridge.injectBridgeJavaScript()
        ucc.addUserScript(WKUserScript(source: bridgeJs, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: flags, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.add(bridge, name: "InsulationNativeBridge")

        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.bounces = true
        wv.isHidden = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView = wv

        let tap = UITapGestureRecognizer(target: self, action: #selector(onUserTouch))
        tap.cancelsTouchesInView = false
        wv.addGestureRecognizer(tap)
    }

    private func setupSplash() {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor(red: 0.05, green: 0.01, blue: 0.01, alpha: 1)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        if let img = UIImage(named: "Splash") ?? loadBundledSplash() {
            imageView.image = img
        } else {
            imageView.backgroundColor = UIColor(red: 0.35, green: 0.0, blue: 0.0, alpha: 1)
        }
        panel.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: panel.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        ])

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "3"
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.83, green: 0.69, blue: 0.31, alpha: 1)
        label.font = .boldSystemFont(ofSize: 18)
        label.backgroundColor = UIColor(white: 0, alpha: 0.45)
        label.layer.cornerRadius = 24
        label.clipsToBounds = true
        panel.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.topAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            label.widthAnchor.constraint(equalToConstant: 48),
            label.heightAnchor.constraint(equalToConstant: 48)
        ])
        splashView = panel
        countdownLabel = label
    }

    private func loadBundledSplash() -> UIImage? {
        Bundle.main.url(forResource: "splash", withExtension: "png", subdirectory: "www")
            .flatMap { UIImage(contentsOfFile: $0.path) }
        ?? Bundle.main.url(forResource: "beijingtu", withExtension: "png", subdirectory: "www")
            .flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private func wwwRootURL() -> URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("www", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // 开发态：从仓库 ios-app/www 读取
        let dev = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("www", isDirectory: true)
        return dev
    }

    private func loadStartPage() {
        let root = wwwRootURL()
        let entry = AppConfig.assetsEntry.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let page = root.appendingPathComponent(entry)
        webView.loadFileURL(page, allowingReadAccessTo: root)
    }

    private func startSplashCountdown() {
        var left = max(1, AppConfig.splashDurationMs / 1000)
        countdownLabel.text = "\(left)"
        splashTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            left -= 1
            if left <= 0 {
                timer.invalidate()
                self.finishSplash()
            } else {
                self.countdownLabel.text = "\(left)"
            }
        }
    }

    private func finishSplash() {
        guard !splashFinished else { return }
        splashFinished = true
        splashTimer?.invalidate()
        splashTimer = nil
        splashView.removeFromSuperview()
        webView.isHidden = false
    }

    func setStatusBarColor(hex: String) {
        let color = UIColor(css: hex) ?? view.backgroundColor
        view.backgroundColor = color
        if let c = color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            statusBarStyle = luminance > 0.6 ? .darkContent : .lightContent
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    func setScreenshotProtection(tabId: String) {
        let enable = protectedTabs.contains(tabId)
        contentProtectionEnabled = enable
        if #available(iOS 13.0, *) {
            // 通过隐藏窗口内容降低截屏风险（完整 FLAG_SECURE 无公开 API）
            webView.isOpaque = !enable
        }
        _ = enable
    }

    func syncScreenshotProtection(for url: URL?) {
        guard let url else { return }
        let path = url.path.lowercased()
        let tab = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "tab" })?.value ?? ""
        let tabId: String
        if path.contains("irregular-duct-nail") {
            tabId = "irregular-duct-nail"
        } else if path.hasSuffix("duct-nail.html") || path.hasSuffix("/duct-nail") {
            tabId = "duct-nail"
        } else if path.contains("shell.html") {
            tabId = tab
        } else {
            tabId = ""
        }
        setScreenshotProtection(tabId: tabId)
    }

    func navigateToBaowenHome(payStatus: String?) {
        let root = wwwRootURL()
        var page = root.appendingPathComponent("baowen/shell.html")
        if let status = payStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty,
           var comps = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "pay", value: status)]
            if let u = comps.url { page = u }
        }
        webView.loadFileURL(page, allowingReadAccessTo: root)
    }

    func openGongtianFromReminder() {
        let root = wwwRootURL()
        let page = root.appendingPathComponent("gongtian/app-shell.html")
        webView.loadFileURL(page, allowingReadAccessTo: root)
    }

    func deliverRestoreFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let b64 = data.base64EncodedString()
        let name = url.lastPathComponent
        let script = """
        (function(){
          try {
            var detail = {name: \(jsonString(name)), base64: \(jsonString(b64))};
            window.dispatchEvent(new CustomEvent('gongtian-restore-file', {detail: detail}));
            if (window.onNativeRestoreFile) window.onNativeRestoreFile(detail);
          } catch(e){}
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc private func onUserTouch() {
        let now = Date().timeIntervalSince1970
        lastUserGestureAt = now
        if payPageReadyAt > 0, now >= payPageReadyAt {
            userArmedPayLaunch = true
        }
    }

    // MARK: - WKUIDelegate prompt bridge

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        if let result = bridge.handlePrompt(prompt) {
            completionHandler(result)
            return
        }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - Navigation / Pay

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let raw = url.absoluteString
        let lower = raw.lowercased()

        if isAlipayHttpsAppLink(lower) {
            if canLaunchPayApp(hasGesture: navigationAction.navigationType != .other, isRedirect: navigationAction.navigationType == .other) {
                openExternal(url)
            }
            decisionHandler(.cancel)
            return
        }

        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") || lower.hasPrefix("about:") || lower.hasPrefix("blob:")) {
            if isAppPayLaunchUrl(lower) {
                if canLaunchPayApp(hasGesture: navigationAction.navigationType == .linkActivated, isRedirect: false) {
                    openExternal(url)
                }
                decisionHandler(.cancel)
                return
            }
            if canLaunchPayApp(hasGesture: navigationAction.navigationType == .linkActivated, isRedirect: false) {
                openExternal(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let u = webView.url?.absoluteString ?? ""
        if u.lowercased().hasPrefix("file:") || isNewPayEntryUrl(u) {
            resetPayLaunchState()
        }
        syncScreenshotProtection(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncScreenshotProtection(for: webView.url)
        let u = webView.url?.absoluteString ?? ""
        if u.lowercased().hasPrefix("http") {
            if payPageReadyAt <= 0 {
                payPageReadyAt = Date().timeIntervalSince1970
                userArmedPayLaunch = false
            }
        } else if u.lowercased().hasPrefix("file:") {
            resetPayLaunchState()
        }
        // file 页补注
        let flags = NativeBridge.injectAppFlagsJavaScript(
            deviceId: DeviceIdProvider.get(),
            insulationApi: AppConfig.insulationApiBase,
            gongtianApi: AppConfig.gongtianApiBase
        )
        webView.evaluateJavaScript(NativeBridge.injectBridgeJavaScript(), completionHandler: nil)
        webView.evaluateJavaScript(flags, completionHandler: nil)
        webView.evaluateJavaScript("""
        (function(){
          try {
            if (window.INSULATION_API_BASE && window.API_CONFIG && API_CONFIG.setBaseUrl) {
              API_CONFIG.setBaseUrl(window.INSULATION_API_BASE);
            }
          } catch(e){}
        })();
        """, completionHandler: nil)
    }

    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func canLaunchPayApp(hasGesture: Bool, isRedirect: Bool) -> Bool {
        if isRedirect { return false }
        if payPageReadyAt <= 0 { return false }
        let now = Date().timeIntervalSince1970
        let pageAge = now - payPageReadyAt
        if pageAge < 1 { return false }
        if userArmedPayLaunch && lastUserGestureAt >= payPageReadyAt && (now - lastUserGestureAt) <= 5 {
            return true
        }
        if hasGesture && pageAge >= 1 { return true }
        return false
    }

    private func resetPayLaunchState() {
        lastUserGestureAt = 0
        payPageReadyAt = 0
        userArmedPayLaunch = false
    }

    private func isAppPayLaunchUrl(_ lower: String) -> Bool {
        if lower.hasPrefix("alipays:") || lower.hasPrefix("alipay:") { return true }
        if lower.hasPrefix("weixin:") || lower.hasPrefix("wechat:") || lower.hasPrefix("wx:") { return true }
        if lower.hasPrefix("mqqapi:") || lower.hasPrefix("mqq:") { return true }
        if lower.hasPrefix("intent:") && (lower.contains("alipay") || lower.contains("weixin") || lower.contains("tencent.mm")) {
            return true
        }
        return lower.contains("alipay") && !lower.hasPrefix("http")
    }

    private func isAlipayHttpsAppLink(_ lower: String) -> Bool {
        guard lower.hasPrefix("http") else { return false }
        if lower.contains("ds.alipay.") || lower.contains("mclient.alipay.") ||
            lower.contains("render.alipay.") || lower.contains("ulink.alipay.") ||
            lower.contains("qr.alipay.") {
            return true
        }
        return lower.contains("platformapi") || lower.contains("startapp") || lower.contains("scheme=alipay")
    }

    private func isNewPayEntryUrl(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.hasPrefix("http") else { return false }
        return lower.contains("submit.php") ||
            (lower.contains("out_trade_no=") && lower.contains("sign=")) ||
            (lower.contains("type=alipay") && lower.contains("pid=")) ||
            (lower.contains("type=wxpay") && lower.contains("pid="))
    }

    private func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [])
        if let data, let s = String(data: data, encoding: .utf8) { return s }
        return "\"\""
    }
}

private extension UIColor {
    convenience init?(css: String) {
        var hex = css.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        if hex.count == 6 {
            self.init(
                red: CGFloat((value & 0xFF0000) >> 16) / 255,
                green: CGFloat((value & 0x00FF00) >> 8) / 255,
                blue: CGFloat(value & 0x0000FF) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: CGFloat((value & 0xFF000000) >> 24) / 255,
                green: CGFloat((value & 0x00FF0000) >> 16) / 255,
                blue: CGFloat((value & 0x0000FF00) >> 8) / 255,
                alpha: CGFloat(value & 0x000000FF) / 255
            )
        }
    }
}
