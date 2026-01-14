import Foundation
import SwiftData

/// 重复周期
enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "daily"       // 每天
    case weekly = "weekly"     // 每周
    case monthly = "monthly"   // 每月

    var displayName: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }
}

/// 定期交易模板
@Model
final class RecurringTransaction {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// 交易名称/备注
    var name: String = ""

    /// 金额
    var amount: Decimal = 0

    /// 交易类型
    var type: TransactionType = TransactionType.expense

    /// 分类 ID
    var categoryId: UUID?

    /// 付款人 ID
    var payerId: UUID?

    /// 参与人 IDs
    var participantIds: [UUID] = []

    /// 商户
    var merchant: String = ""

    /// 重复周期
    var frequency: RecurringFrequency = RecurringFrequency.daily

    /// 每周的哪一天 (0=周日, 1=周一, ..., 6=周六)，仅用于 weekly
    var weekday: Int?

    /// 每月的哪一天 (1-31)，仅用于 monthly
    var dayOfMonth: Int?

    /// 是否启用
    var isEnabled: Bool = true

    /// 上次执行日期
    var lastExecutedDate: Date?

    init(
        name: String,
        amount: Decimal,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        payerId: UUID? = nil,
        participantIds: [UUID] = [],
        merchant: String = "",
        frequency: RecurringFrequency = .daily,
        weekday: Int? = nil,
        dayOfMonth: Int? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.name = name
        self.amount = amount
        self.type = type
        self.categoryId = categoryId
        self.payerId = payerId
        self.participantIds = participantIds
        self.merchant = merchant
        self.frequency = frequency
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.isEnabled = true
    }

    /// 检查是否需要执行（今天应执行或有遗漏的记录）
    func shouldExecuteToday() -> Bool {
        guard isEnabled else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 检查今天是否已经执行过
        if let lastDate = lastExecutedDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            if lastDay == today {
                return false // 今天已经执行过了
            }
        }

        switch frequency {
        case .daily:
            // 每天都需要执行，只要今天没执行过就返回 true
            return true

        case .weekly:
            guard let targetWeekday = weekday else { return false }
            let currentWeekday = calendar.component(.weekday, from: today)
            // Calendar.weekday: 1=周日, 2=周一, ..., 7=周六
            // 我们的 weekday: 0=周日, 1=周一, ..., 6=周六
            let targetCalendarWeekday = targetWeekday + 1

            // 今天就是目标日期
            if currentWeekday == targetCalendarWeekday {
                return true
            }

            // 检查本周是否有遗漏（目标日期已过但未执行）
            let daysSinceTarget = currentWeekday - targetCalendarWeekday
            if daysSinceTarget > 0 {
                // 本周的目标日期已过
                let targetDate = calendar.date(byAdding: .day, value: -daysSinceTarget, to: today)!
                if let lastDate = lastExecutedDate {
                    let lastDay = calendar.startOfDay(for: lastDate)
                    // 如果上次执行在本周目标日期之前，说明有遗漏
                    return lastDay < targetDate
                } else {
                    // 从未执行过
                    return true
                }
            }

            return false

        case .monthly:
            guard let targetDay = dayOfMonth else { return false }
            let currentDay = calendar.component(.day, from: today)

            // 今天就是目标日期
            if currentDay == targetDay {
                return true
            }

            // 检查本月是否有遗漏（目标日期已过但未执行）
            if currentDay > targetDay {
                // 本月的目标日期已过
                var components = calendar.dateComponents([.year, .month], from: today)
                components.day = targetDay
                if let targetDate = calendar.date(from: components) {
                    if let lastDate = lastExecutedDate {
                        let lastDay = calendar.startOfDay(for: lastDate)
                        // 如果上次执行在本月目标日期之前，说明有遗漏
                        return lastDay < targetDate
                    } else {
                        // 从未执行过
                        return true
                    }
                }
            }

            return false
        }
    }
}
