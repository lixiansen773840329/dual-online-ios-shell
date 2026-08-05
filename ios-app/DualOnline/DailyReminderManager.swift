import Foundation
import UserNotifications

final class DailyReminderManager {
    static let shared = DailyReminderManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let keyEnabled = "daily_reminder_enabled"
    private let keyHour = "daily_reminder_hour"
    private let keyMinute = "daily_reminder_minute"
    private let keySoundTitle = "daily_reminder_sound_title"
    private let notifId = "gongtian.daily.reminder"

    private init() {}

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func settingsJSON() -> String {
        let enabled = defaults.bool(forKey: keyEnabled)
        let hour = defaults.object(forKey: keyHour) as? Int ?? 20
        let minute = defaults.object(forKey: keyMinute) as? Int ?? 0
        let soundTitle = defaults.string(forKey: keySoundTitle) ?? "系统默认"
        let dict: [String: Any] = [
            "supported": true,
            "enabled": enabled,
            "hour": hour,
            "minute": minute,
            "soundTitle": soundTitle,
            "soundUri": "",
            "canScheduleExactAlarm": true,
            "nextTriggerAt": nextTriggerAt(hour: hour, minute: minute, enabled: enabled)
        ]
        return jsonString(dict)
    }

    func saveSettingsJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return jsonString(["ok": false, "message": "参数无效"])
        }
        let enabled = obj["enabled"] as? Bool ?? false
        let hour = min(23, max(0, obj["hour"] as? Int ?? 20))
        let minute = min(59, max(0, obj["minute"] as? Int ?? 0))
        let soundTitle = (obj["soundTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(enabled, forKey: keyEnabled)
        defaults.set(hour, forKey: keyHour)
        defaults.set(minute, forKey: keyMinute)
        if let soundTitle, !soundTitle.isEmpty {
            defaults.set(soundTitle, forKey: keySoundTitle)
        }
        requestPermission()
        if enabled {
            schedule(hour: hour, minute: minute)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [notifId])
        }
        return jsonString([
            "ok": true,
            "scheduled": enabled,
            "needExactAlarm": false,
            "nextTriggerAt": nextTriggerAt(hour: hour, minute: minute, enabled: enabled),
            "message": enabled ? "提醒已开启" : "提醒已关闭",
            "soundTitle": defaults.string(forKey: keySoundTitle) ?? "系统默认",
            "soundUri": "",
            "canScheduleExactAlarm": true
        ])
    }

    private func schedule(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [notifId])
        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let content = UNMutableNotificationContent()
        content.title = "今天的工天信息你记录了吗"
        content.body = "打开双端随行录，记录今日工天"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(identifier: notifId, content: content, trigger: trigger)
        center.add(req, withCompletionHandler: nil)
    }

    private func nextTriggerAt(hour: Int, minute: Int, enabled: Bool) -> Int64 {
        guard enabled else { return 0 }
        var cal = Calendar.current
        cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard var date = cal.date(from: comps) else { return 0 }
        if date.timeIntervalSinceNow <= 0 {
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
