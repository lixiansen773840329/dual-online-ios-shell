import Foundation
import UIKit

enum DownloadHelper {
    static func saveBase64(_ base64: String, filename: String, mimeType: String, from controller: UIViewController?) {
        guard let controller else { return }
        var raw = base64
        if let range = raw.range(of: "base64,") {
            raw = String(raw[range.upperBound...])
        }
        guard let data = Data(base64Encoded: raw, options: [.ignoreUnknownCharacters]) else {
            presentAlert(on: controller, message: "文件解码失败")
            return
        }
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName.isEmpty ? "download.bin" : safeName)
        do {
            try data.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = activity.popoverPresentationController {
                pop.sourceView = controller.view
                pop.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            }
            controller.present(activity, animated: true)
        } catch {
            presentAlert(on: controller, message: "保存失败: \(error.localizedDescription)")
        }
        _ = mimeType
    }

    private static func presentAlert(on controller: UIViewController, message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        controller.present(alert, animated: true)
    }
}
