import Foundation

/// CSV 导入服务 - 处理 app 原生 CSV 格式的解析
struct CSVImportService {

    /// App 导出的 CSV 文件的标准列头
    static let nativeCSVHeader = "id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at"

    /// 检测是否是 app 导出的原生 CSV 格式
    static func isNativeFormat(content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let firstLine = lines.first else { return false }
        return firstLine == nativeCSVHeader
    }

    /// 解析 app 导出的原生 CSV 格式
    /// - Parameter content: CSV 文件内容
    /// - Returns: 解析后的交易草稿列表
    static func parseNativeCSV(content: String) -> [TransactionDraft] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // 跳过列头
        guard lines.count > 1 else { return [] }
        let dataLines = Array(lines.dropFirst())

        return parseNativeCSVLines(dataLines)
    }

    /// 解析 CSV 数据行（不包含列头）
    static func parseNativeCSVLines(_ lines: [String]) -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        let dateFormatter = ISO8601DateFormatter()

        for line in lines {
            let fields = parseCSVLine(line)

            // 列顺序: id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at
            guard fields.count >= 10 else { continue }

            let dateStr = fields[1]
            let amountStr = fields[2]
            let typeStr = fields[3]
            let note = fields[7]
            let merchant = fields[8]
            let sourceStr = fields[9]

            guard let date = dateFormatter.date(from: dateStr),
                  let amount = Decimal(string: amountStr) else {
                continue
            }

            let type: TransactionType = typeStr == "income" ? .income : .expense
            let source: TransactionSource = TransactionSource(rawValue: sourceStr) ?? .text

            let draft = TransactionDraft(
                date: date,
                amount: amount,
                type: type,
                note: note,
                merchant: merchant,
                source: source
            )
            drafts.append(draft)
        }

        return drafts
    }

    /// 解析 CSV 行（处理引号和逗号）
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)

        return fields
    }
}
