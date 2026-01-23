import Foundation
import SwiftData

/// 提醒频率类型
enum ReminderFrequency: String, Codable, CaseIterable {
    case daily = "每日"
    case monthly = "每月"

    var description: String {
        rawValue
    }
}

/// 记账提醒模型
@Model
final class AccountingReminder {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    var message: String
    var frequency: ReminderFrequency
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    /// 用于通知的唯一标识符
    var notificationIdentifier: String {
        "accounting_reminder_\(id.uuidString)"
    }

    /// 格式化的时间字符串
    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    init(
        id: UUID = UUID(),
        hour: Int = 14,
        minute: Int = 0,
        message: String = "记账时间到了，赶紧记一笔吧！",
        frequency: ReminderFrequency = .daily,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.message = message
        self.frequency = frequency
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
