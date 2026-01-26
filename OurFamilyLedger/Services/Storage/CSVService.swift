import Foundation

/// CSV 服务错误
enum CSVError: LocalizedError {
    case invalidFormat
    case fileNotFound
    case writeError(Error)
    case readError(Error)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "CSV 格式无效"
        case .fileNotFound:
            return "文件不存在"
        case .writeError(let error):
            return "写入失败: \(error.localizedDescription)"
        case .readError(let error):
            return "读取失败: \(error.localizedDescription)"
        case .parseError(let message):
            return "解析失败: \(message)"
        }
    }
}

/// CSV 读写服务
actor CSVService {
    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let datOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - File Paths

    /// 获取账本文件夹路径
    func ledgerFolderURL(iCloudPath: String?) -> URL {
        if let iCloudPath = iCloudPath,
           let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
               .appendingPathComponent("Documents")
               .appendingPathComponent(iCloudPath) {
            return iCloudURL
        }
        // 本地文档目录
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledger")
    }

    /// 获取交易文件路径（按月）
    func transactionsFileURL(for yearMonth: String, in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("transactions_\(yearMonth).csv")
    }

    /// 获取成员文件路径
    func membersFileURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("members.csv")
    }

    /// 获取分类文件路径
    func categoriesFileURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("categories.csv")
    }

    /// 获取设置文件路径
    func settingsFileURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("settings.json")
    }

    // MARK: - Directory Management

    /// 确保文件夹存在
    func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Transaction CSV

    /// 读取交易记录
    func readTransactions(from fileURL: URL) throws -> [TransactionCSV] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw CSVError.readError(error)
        }

        return try parseTransactionsCSV(content)
    }

    /// 从内容字符串解析交易记录（用于冲突解决）
    func parseTransactionsFromContent(_ content: String) throws -> [TransactionCSV] {
        return try parseTransactionsCSV(content)
    }

    /// 写入交易记录
    func writeTransactions(_ transactions: [TransactionCSV], to fileURL: URL) throws {
        let content = generateTransactionsCSV(transactions)

        do {
            try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw CSVError.writeError(error)
        }
    }

    /// 追加单条交易
    func appendTransaction(_ transaction: TransactionCSV, to fileURL: URL) throws {
        var transactions = try readTransactions(from: fileURL)
        transactions.append(transaction)
        try writeTransactions(transactions, to: fileURL)
    }

    /// 更新交易
    func updateTransaction(_ transaction: TransactionCSV, in fileURL: URL) throws {
        var transactions = try readTransactions(from: fileURL)
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
            try writeTransactions(transactions, to: fileURL)
        }
    }

    /// 删除交易
    func deleteTransaction(id: String, from fileURL: URL) throws {
        var transactions = try readTransactions(from: fileURL)
        transactions.removeAll { $0.id == id }
        try writeTransactions(transactions, to: fileURL)
    }

    // MARK: - Member CSV

    /// 读取成员
    func readMembers(from fileURL: URL) throws -> [MemberCSV] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw CSVError.readError(error)
        }

        return try parseMembersCSV(content)
    }

    /// 写入成员
    func writeMembers(_ members: [MemberCSV], to fileURL: URL) throws {
        let content = generateMembersCSV(members)

        do {
            try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw CSVError.writeError(error)
        }
    }

    // MARK: - Category CSV

    /// 读取分类
    func readCategories(from fileURL: URL) throws -> [CategoryCSV] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw CSVError.readError(error)
        }

        return try parseCategoriesCSV(content)
    }

    /// 写入分类
    func writeCategories(_ categories: [CategoryCSV], to fileURL: URL) throws {
        let content = generateCategoriesCSV(categories)

        do {
            try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw CSVError.writeError(error)
        }
    }

    // MARK: - Settings JSON

    /// 读取设置
    func readSettings(from fileURL: URL) throws -> LedgerSettings {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LedgerSettings()
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CSVError.readError(error)
        }

        return try JSONDecoder().decode(LedgerSettings.self, from: data)
    }

    /// 写入设置
    func writeSettings(_ settings: LedgerSettings, to fileURL: URL) throws {
        do {
            try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw CSVError.writeError(error)
        }
    }

    // MARK: - CSV Parsing

    private func parseTransactionsCSV(_ content: String) throws -> [TransactionCSV] {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { return [] }

        var transactions: [TransactionCSV] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)

            guard fields.count >= 12 else {
                throw CSVError.parseError("第 \(index + 2) 行字段数量不足")
            }

            let transaction = TransactionCSV(
                id: fields[0],
                createdAt: fields[1],
                updatedAt: fields[2],
                date: fields[3],
                amount: fields[4],
                type: fields[5],
                category: fields[6],
                payer: fields[7],
                participants: fields[8],
                note: fields[9],
                merchant: fields[10],
                source: fields[11],
                ocrText: fields.count > 12 ? fields[12] : nil,
                currency: fields.count > 13 ? fields[13] : "CNY"
            )
            transactions.append(transaction)
        }

        return transactions
    }

    private func parseMembersCSV(_ content: String) throws -> [MemberCSV] {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { return [] }

        var members: [MemberCSV] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)

            guard fields.count >= 7 else {
                throw CSVError.parseError("第 \(index + 2) 行字段数量不足")
            }

            let member = MemberCSV(
                id: fields[0],
                name: fields[1],
                nickname: fields[2],
                role: fields[3],
                avatarColor: fields[4],
                iCloudIdentifier: fields.count > 5 && !fields[5].isEmpty ? fields[5] : nil,
                createdAt: fields[6],
                updatedAt: fields.count > 7 ? fields[7] : fields[6]
            )
            members.append(member)
        }

        return members
    }

    private func parseCategoriesCSV(_ content: String) throws -> [CategoryCSV] {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { return [] }

        var categories: [CategoryCSV] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)

            guard fields.count >= 7 else {
                throw CSVError.parseError("第 \(index + 2) 行字段数量不足")
            }

            let category = CategoryCSV(
                id: fields[0],
                name: fields[1],
                icon: fields[2],
                color: fields[3],
                type: fields[4],
                isDefault: fields[5],
                sortOrder: fields[6],
                createdAt: fields.count > 7 ? fields[7] : "",
                updatedAt: fields.count > 8 ? fields[8] : ""
            )
            categories.append(category)
        }

        return categories
    }

    /// 解析 CSV 行（处理引号和逗号）
    private func parseCSVLine(_ line: String) -> [String] {
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

    // MARK: - CSV Generation

    private func generateTransactionsCSV(_ transactions: [TransactionCSV]) -> String {
        var lines = [TransactionCSV.headers.joined(separator: ",")]

        for transaction in transactions {
            let fields = [
                escapeCSVField(transaction.id),
                escapeCSVField(transaction.createdAt),
                escapeCSVField(transaction.updatedAt),
                escapeCSVField(transaction.date),
                escapeCSVField(transaction.amount),
                escapeCSVField(transaction.type),
                escapeCSVField(transaction.category),
                escapeCSVField(transaction.payer),
                escapeCSVField(transaction.participants),
                escapeCSVField(transaction.note),
                escapeCSVField(transaction.merchant),
                escapeCSVField(transaction.source),
                escapeCSVField(transaction.ocrText ?? ""),
                escapeCSVField(transaction.currency)
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private func generateMembersCSV(_ members: [MemberCSV]) -> String {
        var lines = [MemberCSV.headers.joined(separator: ",")]

        for member in members {
            let fields = [
                escapeCSVField(member.id),
                escapeCSVField(member.name),
                escapeCSVField(member.nickname),
                escapeCSVField(member.role),
                escapeCSVField(member.avatarColor),
                escapeCSVField(member.iCloudIdentifier ?? ""),
                escapeCSVField(member.createdAt),
                escapeCSVField(member.updatedAt)
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private func generateCategoriesCSV(_ categories: [CategoryCSV]) -> String {
        var lines = [CategoryCSV.headers.joined(separator: ",")]

        for category in categories {
            let fields = [
                escapeCSVField(category.id),
                escapeCSVField(category.name),
                escapeCSVField(category.icon),
                escapeCSVField(category.color),
                escapeCSVField(category.type),
                escapeCSVField(category.isDefault),
                escapeCSVField(category.sortOrder),
                escapeCSVField(category.createdAt),
                escapeCSVField(category.updatedAt)
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// 转义 CSV 字段
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    // MARK: - Utility

    /// 获取月份字符串
    func yearMonthString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    /// 列出所有交易文件
    func listTransactionFiles(in folderURL: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: folderURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
        return contents
            .filter { $0.hasPrefix("transactions_") && $0.hasSuffix(".csv") }
            .sorted()
    }
}
