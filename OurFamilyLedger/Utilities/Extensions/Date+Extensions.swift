import Foundation

extension Date {
    /// ISO 8601 格式字符串
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// 日期字符串 (yyyy-MM-dd)
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    /// 年月字符串 (yyyy-MM)
    var yearMonthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: self)
    }

    /// 友好的日期显示
    var friendlyString: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(self) {
            return "今天"
        } else if calendar.isDateInYesterday(self) {
            return "昨天"
        } else if calendar.isDateInTomorrow(self) {
            return "明天"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")

            if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
                formatter.dateFormat = "M月d日"
            } else {
                formatter.dateFormat = "yyyy年M月d日"
            }

            return formatter.string(from: self)
        }
    }

    /// 相对时间显示
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// 获取月份的开始日期
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    /// 获取月份的结束日期
    var endOfMonth: Date {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return self
        }
        return calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? self
    }

    /// 获取一天的开始
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// 获取一天的结束
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
}

extension String {
    /// 从 ISO 8601 字符串解析日期
    var iso8601Date: Date? {
        ISO8601DateFormatter().date(from: self)
    }

    /// 从日期字符串解析 (yyyy-MM-dd)
    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: self)
    }
}
