import Foundation

extension Decimal {
    /// 格式化为货币字符串
    func formatted(currency: String = "CNY") -> String {
        let symbol = SupportedCurrency(rawValue: currency)?.symbol ?? "¥"
        let number = NSDecimalNumber(decimal: self)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        if let formatted = formatter.string(from: number) {
            return "\(symbol)\(formatted)"
        }
        return "\(symbol)\(number.doubleValue)"
    }

    /// 格式化为简短形式（如 1.2K, 3.5M）
    func formattedCompact() -> String {
        let number = NSDecimalNumber(decimal: self).doubleValue

        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        } else {
            return String(format: "%.2f", number)
        }
    }

    /// 转换为 Double
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

extension Double {
    /// 转换为 Decimal
    var decimal: Decimal {
        Decimal(self)
    }
}
