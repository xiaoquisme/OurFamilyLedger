import Foundation
import SwiftData

/// 重复周期
enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "daily"       // 每天
    case weekly = "weekly"     // 每周
    case monthly = "monthly"   // 每月
    case yearly = "yearly"     // 每年

    var displayName: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
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

    /// 间隔（例如：每2天、每3周）
    var interval: Int = 1

    /// 每周的哪一天 (0=周日, 1=周一, ..., 6=周六)，仅用于 weekly
    var weekday: Int?

    /// 每周的哪几天（支持多选，例如：周一和周三），仅用于 weekly
    var weekdays: [Int] = []

    /// 每月的哪一天 (1-31)，仅用于 monthly
    var dayOfMonth: Int?

    /// 每年的月份 (1-12)，仅用于 yearly
    var monthOfYear: Int?

    /// 是否自动添加（true: 自动添加，false: 手动确认）
    var autoAdd: Bool = false

    /// 结束日期（可选，nil 表示永不结束）
    var endDate: Date?

    /// 重复次数限制（可选，nil 表示无限制）
    var occurrenceCount: Int?

    /// 已执行次数
    var executedCount: Int = 0

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
        interval: Int = 1,
        weekday: Int? = nil,
        weekdays: [Int] = [],
        dayOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        autoAdd: Bool = false,
        endDate: Date? = nil,
        occurrenceCount: Int? = nil
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
        self.interval = interval
        self.weekday = weekday
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.monthOfYear = monthOfYear
        self.autoAdd = autoAdd
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
        self.isEnabled = true
        self.executedCount = 0
    }

    /// 检查是否需要执行（今天应执行或有遗漏的记录）
    func shouldExecuteToday() -> Bool {
        guard isEnabled else { return false }

        // 检查是否已达到执行次数限制
        if let count = occurrenceCount, executedCount >= count {
            return false
        }

        // 检查是否已超过结束日期
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let end = endDate, today > calendar.startOfDay(for: end) {
            return false
        }

        // 检查今天是否已经执行过
        if let lastDate = lastExecutedDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            if lastDay == today {
                return false // 今天已经执行过了
            }
        }

        switch frequency {
        case .daily:
            // 每 N 天执行一次
            if let lastDate = lastExecutedDate {
                let daysSinceLastExecution = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate), to: today).day ?? 0
                return daysSinceLastExecution >= interval
            }
            // 从未执行过，应该执行
            return true

        case .weekly:
            // 支持单个星期或多个星期
            let currentWeekday = calendar.component(.weekday, from: today)
            // Calendar.weekday: 1=周日, 2=周一, ..., 7=周六
            // 我们的 weekday: 0=周日, 1=周一, ..., 6=周六
            let currentWeekdayIndex = (currentWeekday + 6) % 7

            // 如果使用 weekdays 数组（多选）
            if !weekdays.isEmpty {
                guard weekdays.contains(currentWeekdayIndex) else { return false }
            } else if let targetWeekday = weekday {
                // 使用单个 weekday
                guard targetWeekday == currentWeekdayIndex else { return false }
            } else {
                return false
            }

            // 检查间隔（每 N 周）
            if interval > 1, let lastDate = lastExecutedDate {
                let weeksSinceLastExecution = calendar.dateComponents([.weekOfYear], from: calendar.startOfDay(for: lastDate), to: today).weekOfYear ?? 0
                return weeksSinceLastExecution >= interval
            }

            return true

        case .monthly:
            guard let targetDay = dayOfMonth else { return false }
            let currentDay = calendar.component(.day, from: today)

            // 今天不是目标日期
            guard currentDay == targetDay else { return false }

            // 检查间隔（每 N 月）
            if interval > 1, let lastDate = lastExecutedDate {
                let monthsSinceLastExecution = calendar.dateComponents([.month], from: calendar.startOfDay(for: lastDate), to: today).month ?? 0
                return monthsSinceLastExecution >= interval
            }

            return true

        case .yearly:
            guard let targetMonth = monthOfYear, let targetDay = dayOfMonth else { return false }
            let currentMonth = calendar.component(.month, from: today)
            let currentDay = calendar.component(.day, from: today)

            // 今天不是目标日期
            guard currentMonth == targetMonth && currentDay == targetDay else { return false }

            // 检查间隔（每 N 年）
            if interval > 1, let lastDate = lastExecutedDate {
                let yearsSinceLastExecution = calendar.dateComponents([.year], from: calendar.startOfDay(for: lastDate), to: today).year ?? 0
                return yearsSinceLastExecution >= interval
            }

            return true
        }
    }

    /// 获取重复规则的描述文本
    var recurrenceDescription: String {
        var desc = ""
        
        // 基本频率
        if interval == 1 {
            desc = frequency.displayName
        } else {
            switch frequency {
            case .daily:
                desc = "每\(interval)天"
            case .weekly:
                desc = "每\(interval)周"
            case .monthly:
                desc = "每\(interval)月"
            case .yearly:
                desc = "每\(interval)年"
            }
        }
        
        // 具体时间
        switch frequency {
        case .weekly:
            let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            if !weekdays.isEmpty {
                let names = weekdays.sorted().map { weekdayNames[$0] }
                desc += "（\(names.joined(separator: "、"))）"
            } else if let wd = weekday {
                desc += "（\(weekdayNames[wd])）"
            }
        case .monthly:
            if let day = dayOfMonth {
                desc += "（\(day)号）"
            }
        case .yearly:
            if let month = monthOfYear, let day = dayOfMonth {
                desc += "（\(month)月\(day)日）"
            }
        case .daily:
            break
        }
        
        return desc
    }
}
