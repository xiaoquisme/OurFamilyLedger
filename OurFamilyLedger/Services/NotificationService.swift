import Foundation
import UserNotifications

/// 通知服务协议
protocol NotificationServiceProtocol {
    func requestAuthorization() async -> Bool
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    func scheduleReminder(_ reminder: AccountingReminder) async
    func updateSingleReminder(_ reminder: AccountingReminder) async
    func cancelReminder(_ reminder: AccountingReminder)
    func syncAllReminders(_ reminders: [AccountingReminder]) async
    func cancelAllReminders()
}

/// 本地通知服务
class NotificationService: NotificationServiceProtocol {
    static var shared: NotificationServiceProtocol = NotificationService()

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

    // MARK: - 多提醒支持

    /// 为单个 AccountingReminder 设置通知
    func scheduleReminder(_ reminder: AccountingReminder) async {
        guard reminder.isEnabled else { return }

        // 请求权限
        let granted = await requestAuthorization()
        guard granted else {
            print("通知权限未授权")
            return
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "记账提醒"
        content.body = reminder.message
        content.sound = .default

        // 设置触发时间
        var dateComponents = DateComponents()
        dateComponents.hour = reminder.hour
        dateComponents.minute = reminder.minute

        if reminder.frequency == .monthly {
            dateComponents.day = 1
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            let freqDesc = reminder.frequency == .daily ? "每天" : "每月1日"
            print("✅ 提醒已设置（\(freqDesc) \(reminder.timeString)）")
        } catch {
            print("设置提醒失败: \(error)")
        }
    }

    /// 更新单个 AccountingReminder 的通知
    func updateSingleReminder(_ reminder: AccountingReminder) async {
        // 先取消旧的
        cancelReminder(reminder)
        // 重新设置
        await scheduleReminder(reminder)
    }

    /// 取消单个 AccountingReminder 的通知
    func cancelReminder(_ reminder: AccountingReminder) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminder.notificationIdentifier])
        print("❌ 提醒已取消（\(reminder.timeString)）")
    }

    /// 同步所有提醒（启动时调用）
    func syncAllReminders(_ reminders: [AccountingReminder]) async {
        // 先取消所有旧提醒
        let identifiers = reminders.map { $0.notificationIdentifier }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)

        // 重新设置所有启用的提醒
        for reminder in reminders where reminder.isEnabled {
            await scheduleReminder(reminder)
        }
    }
}
