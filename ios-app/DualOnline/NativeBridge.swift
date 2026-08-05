import Foundation
import UIKit
import WebKit
import UniformTypeIdentifiers

/// 通过 prompt 实现与 Android @JavascriptInterface 对齐的同步桥接。
final class NativeBridge: NSObject, WKScriptMessageHandler, UIDocumentPickerDelegate {
    weak var controller: ViewController?
    private var pendingRestoreCompletion: ((URL?) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 备用异步通道；主路径为 prompt 同步桥
        guard message.name == "InsulationNativeBridge",
              let body = message.body as? [String: Any],
              let method = body["method"] as? String else { return }
        _ = handle(method: method, args: body["args"] as? [Any] ?? [])
    }

    func handlePrompt(_ prompt: String) -> String? {
        guard prompt.hasPrefix("__BRIDGE__") else { return nil }
        let jsonText = String(prompt.dropFirst("__BRIDGE__".count))
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = obj["method"] as? String else {
            return ""
        }
        let args = obj["args"] as? [Any] ?? []
        return handle(method: method, args: args)
    }

    private func handle(method: String, args: [Any]) -> String {
        switch method {
        case "getDeviceId":
            return DeviceIdProvider.get()
        case "getDeviceLabel":
            return DeviceIdProvider.deviceLabel()
        case "getDeviceType":
            return "mobile"
        case "getSafeAreaTop":
            return String(Int(controller?.safeAreaTop.rounded() ?? 0))
        case "getSafeAreaBottom":
            return String(Int(controller?.safeAreaBottom.rounded() ?? 0))
        case "setStatusBarColor":
            if let hex = args.first as? String {
                DispatchQueue.main.async { self.controller?.setStatusBarColor(hex: hex) }
            }
            return ""
        case "setScreenshotProtectionForTab":
            let tab = (args.first as? String) ?? ""
            DispatchQueue.main.async { self.controller?.setScreenshotProtection(tabId: tab) }
            return ""
        case "saveDownloadFile":
            let b64 = (args.count > 0 ? args[0] as? String : nil) ?? ""
            let name = (args.count > 1 ? args[1] as? String : nil) ?? "download.bin"
            let mime = (args.count > 2 ? args[2] as? String : nil) ?? "application/octet-stream"
            DispatchQueue.main.async {
                DownloadHelper.saveBase64(b64, filename: name, mimeType: mime, from: self.controller)
            }
            return ""
        case "pickRestoreFile":
            DispatchQueue.main.async { self.openRestorePicker() }
            return ""
        case "getDailyReminderSettings":
            return DailyReminderManager.shared.settingsJSON()
        case "saveDailyReminderSettings":
            let json = (args.first as? String) ?? "{}"
            return DailyReminderManager.shared.saveSettingsJSON(json)
        case "openExactAlarmPermissionSettings", "openApplicationPermissionSettings":
            DispatchQueue.main.async {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            return ""
        case "pickDailyReminderSound":
            // iOS 使用默认通知音；返回当前设置即可
            return DailyReminderManager.shared.settingsJSON()
        case "requestNotificationPermission":
            DailyReminderManager.shared.requestPermission()
            return ""
        case "goAppHome":
            let status = args.first as? String
            DispatchQueue.main.async { self.controller?.navigateToBaowenHome(payStatus: status) }
            return ""
        case "exitApp":
            DispatchQueue.main.async {
                UIApplication.shared.perform(Selector(("suspend")))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    exit(0)
                }
            }
            return ""
        default:
            return ""
        }
    }

    private func openRestorePicker() {
        guard let controller else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.text", "public.data"], in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        controller.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        self.controller?.deliverRestoreFile(url: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

    static func injectBridgeJavaScript() -> String {
        """
        (function(){
          if (window.InsulationNativeBridge && window.InsulationNativeBridge.__iosPromptBridge) return;
          function call(method){
            var args = Array.prototype.slice.call(arguments, 1);
            var payload = JSON.stringify({method: method, args: args});
            var ret = prompt('__BRIDGE__' + payload);
            return (ret === null || ret === undefined) ? '' : String(ret);
          }
          var api = {
            __iosPromptBridge: true,
            getDeviceId: function(){ return call('getDeviceId'); },
            getDeviceLabel: function(){ return call('getDeviceLabel'); },
            getDeviceType: function(){ return call('getDeviceType'); },
            getSafeAreaTop: function(){ return parseInt(call('getSafeAreaTop')||'0',10)||0; },
            getSafeAreaBottom: function(){ return parseInt(call('getSafeAreaBottom')||'0',10)||0; },
            setStatusBarColor: function(c){ call('setStatusBarColor', c||''); },
            setScreenshotProtectionForTab: function(t){ call('setScreenshotProtectionForTab', t||''); },
            saveDownloadFile: function(b,f,m){ call('saveDownloadFile', b||'', f||'', m||''); },
            pickRestoreFile: function(){ call('pickRestoreFile'); },
            getDailyReminderSettings: function(){ return call('getDailyReminderSettings'); },
            saveDailyReminderSettings: function(j){ return call('saveDailyReminderSettings', j||'{}'); },
            openExactAlarmPermissionSettings: function(){ call('openExactAlarmPermissionSettings'); },
            openApplicationPermissionSettings: function(){ call('openApplicationPermissionSettings'); },
            pickDailyReminderSound: function(){ call('pickDailyReminderSound'); },
            requestNotificationPermission: function(){ call('requestNotificationPermission'); },
            goAppHome: function(s){ call('goAppHome', s||''); },
            exitApp: function(){ call('exitApp'); }
          };
          window.InsulationNativeBridge = api;
        })();
        """
    }

    static func injectAppFlagsJavaScript(deviceId: String, insulationApi: String, gongtianApi: String) -> String {
        let did = jsonString(deviceId)
        let ins = jsonString(insulationApi)
        let gt = jsonString(gongtianApi)
        return """
        (function(){
          try {
            localStorage.setItem('insulation_device_id', \(did));
            window.__INSULATION_NATIVE_APP__ = true;
            window.__GONGTIAN_NATIVE_APP__ = true;
            window.__DUAL_ONLINE_APP__ = true;
            window.GONGTIAN_LOCAL_PACKAGE = true;
            window.GONGTIAN_LOCAL_FIRST = false;
            document.documentElement.classList.add('gongtian-native-app');
            if (\(ins) !== '') { window.INSULATION_API_BASE = \(ins); }
            if (\(gt) !== '') { window.GONGTIAN_REMOTE_API_BASE = \(gt); window.GONGTIAN_API_BASE = \(gt); }
          } catch (e) {}
        })();
        """
    }

    private static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [])
        if let data, let s = String(data: data, encoding: .utf8) { return s }
        return "\"\""
    }
}
