import Foundation
import UserNotifications

/// 本地通知服务
class NotificationService {
    static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let dailyReminderIdentifier = "daily_accounting_reminder"
    private let monthlyReminderIdentifier = "monthly_accounting_reminder"

    private init() {}

    // MARK: - 权限请求

    /// 请求通知权限
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("请求通知权限失败: \(error)")
            return false
        }
    }

    /// 检查通知权限状态
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - 记账提醒

    /// 设置每日记账提醒
    func scheduleDailyReminder(hour: Int = 14, minute: Int = 0, message: String = "记账时间到了，赶紧记一笔吧！") async {
        // 先取消现有提醒
        cancelDailyReminder()

        // 检查权限
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            print("通知权限未授权")
            return
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "记账提醒"
        content.body = message
        content.sound = .default

        // 设置每天指定时间触发
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("✅ 每日记账提醒已设置（每天 \(String(format: "%02d:%02d", hour, minute))）")
        } catch {
            print("设置每日提醒失败: \(error)")
        }
    }

    /// 设置每月记账提醒（每月1日指定时间）
    func scheduleMonthlyReminder(hour: Int = 14, minute: Int = 0, message: String = "记账时间到了，赶紧记一笔吧！") async {
        // 先取消现有提醒
        cancelMonthlyReminder()

        // 检查权限
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            print("通知权限未授权")
            return
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "记账提醒"
        content.body = message
        content.sound = .default

        // 设置每月1日指定时间触发
        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: monthlyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("✅ 每月记账提醒已设置（每月1日 \(String(format: "%02d:%02d", hour, minute))）")
        } catch {
            print("设置每月提醒失败: \(error)")
        }
    }

    /// 取消每日提醒
    func cancelDailyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        print("❌ 每日记账提醒已取消")
    }

    /// 取消每月提醒
    func cancelMonthlyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [monthlyReminderIdentifier])
        print("❌ 每月记账提醒已取消")
    }

    /// 取消所有记账提醒
    func cancelAllReminders() {
        cancelDailyReminder()
        cancelMonthlyReminder()
    }

    /// 根据设置更新提醒
    func updateReminder(mode: String, hour: Int = 14, minute: Int = 0, message: String = "记账时间到了，赶紧记一笔吧！") async {
        // 先取消所有提醒
        cancelAllReminders()

        switch mode {
        case "daily":
            await scheduleDailyReminder(hour: hour, minute: minute, message: message)
        case "monthly":
            await scheduleMonthlyReminder(hour: hour, minute: minute, message: message)
        default:
            // "off" 或其他值，不设置提醒
            break
        }
    }
}
