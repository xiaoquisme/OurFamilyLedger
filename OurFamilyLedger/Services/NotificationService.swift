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

    /// 设置每日记账提醒（每天下午 2:00）
    func scheduleDailyReminder() async {
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
        content.body = "今天还没有记账哦，记得记录一下今天的支出吧！"
        content.sound = .default

        // 设置每天下午 2:00 触发
        var dateComponents = DateComponents()
        dateComponents.hour = 14
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("✅ 每日记账提醒已设置（每天 14:00）")
        } catch {
            print("设置每日提醒失败: \(error)")
        }
    }

    /// 设置每月记账提醒（每月1日下午 2:00）
    func scheduleMonthlyReminder() async {
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
        content.body = "新的一月开始了，记得记录这个月的支出吧！"
        content.sound = .default

        // 设置每月1日下午 2:00 触发
        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = 14
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: monthlyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("✅ 每月记账提醒已设置（每月1日 14:00）")
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
    func updateReminder(mode: String) async {
        // 先取消所有提醒
        cancelAllReminders()

        switch mode {
        case "daily":
            await scheduleDailyReminder()
        case "monthly":
            await scheduleMonthlyReminder()
        default:
            // "off" 或其他值，不设置提醒
            break
        }
    }
}
