import Foundation
import SwiftData

/// Function Tools 执行服务
@MainActor
final class FunctionToolsService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 默认成员ID (从 UserDefaults 读取)
    private var defaultMemberId: UUID? {
        get {
            guard let idString = UserDefaults.standard.string(forKey: "defaultMemberId"),
                  let id = UUID(uuidString: idString) else {
                return nil
            }
            return id
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: "defaultMemberId")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultMemberId")
            }
        }
    }

    /// 执行 Function Call
    func execute(_ functionCall: FunctionCall) async -> FunctionToolResult {
        guard let tool = functionCall.tool else {
            return .failure("未知的工具: \(functionCall.name)")
        }

        do {
            let result = try await executeTool(tool, arguments: functionCall.arguments)
            return .success(result)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func executeTool(_ tool: FunctionTool, arguments: String) async throws -> Any {
        let args = try parseArguments(arguments)

        switch tool {
        // 交易相关
        case .addTransaction:
            return try await addTransaction(args)
        case .listTransactions:
            return try await listTransactions(args)
        case .getTransaction:
            return try await getTransaction(args)
        case .updateTransaction:
            return try await updateTransaction(args)
        case .deleteTransaction:
            return try await deleteTransaction(args)
        case .searchTransactions:
            return try await searchTransactions(args)

        // 分类相关
        case .listCategories:
            return try await listCategories(args)
        case .addCategory:
            return try await addCategory(args)
        case .updateCategory:
            return try await updateCategory(args)
        case .deleteCategory:
            return try await deleteCategory(args)

        // 成员相关
        case .listMembers:
            return try await listMembers()
        case .addMember:
            return try await addMember(args)
        case .updateMember:
            return try await updateMember(args)
        case .deleteMember:
            return try await deleteMember(args)
        case .setDefaultMember:
            return try await setDefaultMember(args)

        // 报表相关
        case .getMonthlySummary:
            return try await getMonthlySummary(args)
        case .getCategoryBreakdown:
            return try await getCategoryBreakdown(args)
        case .getMemberBreakdown:
            return try await getMemberBreakdown(args)

        // 提醒相关
        case .listReminders:
            return try await listReminders()
        case .addReminder:
            return try await addReminder(args)
        case .updateReminder:
            return try await updateReminder(args)
        case .deleteReminder:
            return try await deleteReminder(args)

        // 定期交易相关
        case .listRecurringTransactions:
            return try await listRecurringTransactions()
        case .addRecurringTransaction:
            return try await addRecurringTransaction(args)
        case .updateRecurringTransaction:
            return try await updateRecurringTransaction(args)
        case .deleteRecurringTransaction:
            return try await deleteRecurringTransaction(args)

        // 数据管理
        case .exportData:
            return try await exportData(args)
        case .getICloudStatus:
            return try await getICloudStatus()
        case .syncData:
            return try await syncData()
        }
    }

    private func parseArguments(_ arguments: String) throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Transaction Tools

extension FunctionToolsService {
    private func addTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let amount = args["amount"] as? Double,
              let typeStr = args["type"] as? String,
              let categoryName = args["category"] as? String else {
            throw FunctionToolError.invalidArguments("缺少必要参数: amount, type, category")
        }

        let type = typeStr == "income" ? TransactionType.income : TransactionType.expense

        // 查找分类
        let categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == categoryName && $0.type == type }
        )
        guard let category = try modelContext.fetch(categoryDescriptor).first else {
            throw FunctionToolError.notFound("分类不存在: \(categoryName)")
        }

        // 解析日期
        let date: Date
        if let dateStr = args["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: dateStr) ?? Date()
        } else {
            date = Date()
        }

        // 查找付款人
        var payerId: UUID?
        if let payerName = args["payer"] as? String {
            let memberDescriptor = FetchDescriptor<Member>(
                predicate: #Predicate { $0.name == payerName || $0.nickname == payerName }
            )
            payerId = try modelContext.fetch(memberDescriptor).first?.id
        }

        // 如果没指定付款人，使用默认成员
        if payerId == nil {
            payerId = defaultMemberId
        }

        // 解析参与人
        var participantIds: [UUID] = []
        if let participants = args["participants"] as? [String] {
            for name in participants {
                let descriptor = FetchDescriptor<Member>(
                    predicate: #Predicate { $0.name == name || $0.nickname == name }
                )
                if let member = try modelContext.fetch(descriptor).first {
                    participantIds.append(member.id)
                }
            }
        }

        // 创建交易
        let transaction = TransactionRecord(
            date: date,
            amount: Decimal(amount),
            type: type,
            categoryId: category.id,
            payerId: payerId,
            participantIds: participantIds,
            note: args["note"] as? String ?? "",
            merchant: args["merchant"] as? String ?? "",
            source: .manual
        )

        modelContext.insert(transaction)
        try modelContext.save()

        return [
            "id": transaction.id.uuidString,
            "amount": amount,
            "type": typeStr,
            "category": categoryName,
            "date": formatDate(transaction.date),
            "note": transaction.note ?? "",
            "message": "交易已添加"
        ]
    }

    private func listTransactions(_ args: [String: Any]) async throws -> [[String: Any]] {
        var transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))

        // 应用筛选
        if let startDateStr = args["startDate"] as? String,
           let startDate = parseDate(startDateStr) {
            transactions = transactions.filter { $0.date >= startDate }
        }

        if let endDateStr = args["endDate"] as? String,
           let endDate = parseDate(endDateStr) {
            // endDate 需要包含当天的所有时间，所以使用次日 00:00:00 作为上限
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
            transactions = transactions.filter { $0.date < endOfDay }
        }

        if let typeStr = args["type"] as? String {
            let type = typeStr == "income" ? TransactionType.income : TransactionType.expense
            transactions = transactions.filter { $0.type == type }
        }

        if let categoryName = args["category"] as? String {
            let categories = try modelContext.fetch(FetchDescriptor<Category>())
            if let category = categories.first(where: { $0.name == categoryName }) {
                transactions = transactions.filter { $0.categoryId == category.id }
            }
        }

        let limit = args["limit"] as? Int ?? 20
        transactions = Array(transactions.prefix(limit))

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let members = try modelContext.fetch(FetchDescriptor<Member>())

        return transactions.map { tx in
            let category = categories.first { $0.id == tx.categoryId }
            let payer = members.first { $0.id == tx.payerId }

            return [
                "id": tx.id.uuidString,
                "date": formatDate(tx.date),
                "amount": NSDecimalNumber(decimal: tx.amount).doubleValue,
                "type": tx.type == .income ? "income" : "expense",
                "category": category?.name ?? "未分类",
                "payer": payer?.displayName ?? "",
                "note": tx.note ?? "",
                "merchant": tx.merchant ?? ""
            ]
        }
    }

    private func getTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的交易ID")
        }

        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let transaction = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("交易不存在")
        }

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let members = try modelContext.fetch(FetchDescriptor<Member>())

        let category = categories.first { $0.id == transaction.categoryId }
        let payer = members.first { $0.id == transaction.payerId }
        let participants = members.filter { transaction.participantIds.contains($0.id) }

        return [
            "id": transaction.id.uuidString,
            "date": formatDate(transaction.date),
            "amount": NSDecimalNumber(decimal: transaction.amount).doubleValue,
            "type": transaction.type == .income ? "income" : "expense",
            "category": category?.name ?? "未分类",
            "categoryIcon": category?.icon ?? "",
            "payer": payer?.displayName ?? "",
            "participants": participants.map { $0.displayName },
            "note": transaction.note ?? "",
            "merchant": transaction.merchant ?? "",
            "source": transaction.source.rawValue,
            "createdAt": formatDate(transaction.createdAt)
        ]
    }

    private func updateTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的交易ID")
        }

        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let transaction = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("交易不存在")
        }

        if let amount = args["amount"] as? Double {
            transaction.amount = Decimal(amount)
        }

        if let typeStr = args["type"] as? String {
            transaction.type = typeStr == "income" ? .income : .expense
        }

        if let categoryName = args["category"] as? String {
            let categories = try modelContext.fetch(FetchDescriptor<Category>())
            if let category = categories.first(where: { $0.name == categoryName }) {
                transaction.categoryId = category.id
            }
        }

        if let dateStr = args["date"] as? String, let date = parseDate(dateStr) {
            transaction.date = date
        }

        if let note = args["note"] as? String {
            transaction.note = note
        }

        if let merchant = args["merchant"] as? String {
            transaction.merchant = merchant
        }

        transaction.updatedAt = Date()
        try modelContext.save()

        return [
            "id": transaction.id.uuidString,
            "message": "交易已更新"
        ]
    }

    private func deleteTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的交易ID")
        }

        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let transaction = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("交易不存在")
        }

        modelContext.delete(transaction)
        try modelContext.save()

        return ["message": "交易已删除", "id": idStr]
    }

    private func searchTransactions(_ args: [String: Any]) async throws -> [[String: Any]] {
        guard let keyword = args["keyword"] as? String else {
            throw FunctionToolError.invalidArguments("缺少搜索关键词")
        }

        let limit = args["limit"] as? Int ?? 20
        let lowercaseKeyword = keyword.lowercased()

        var transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))

        transactions = transactions.filter { tx in
            tx.note.lowercased().contains(lowercaseKeyword) ||
            tx.merchant.lowercased().contains(lowercaseKeyword)
        }

        transactions = Array(transactions.prefix(limit))

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let members = try modelContext.fetch(FetchDescriptor<Member>())

        return transactions.map { tx in
            let category = categories.first { $0.id == tx.categoryId }
            let payer = members.first { $0.id == tx.payerId }

            return [
                "id": tx.id.uuidString,
                "date": formatDate(tx.date),
                "amount": NSDecimalNumber(decimal: tx.amount).doubleValue,
                "type": tx.type == .income ? "income" : "expense",
                "category": category?.name ?? "未分类",
                "payer": payer?.displayName ?? "",
                "note": tx.note ?? "",
                "merchant": tx.merchant ?? ""
            ]
        }
    }
}

// MARK: - Category Tools

extension FunctionToolsService {
    private func listCategories(_ args: [String: Any]) async throws -> [[String: Any]] {
        var categories = try modelContext.fetch(FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        ))

        if let typeStr = args["type"] as? String, typeStr != "all" {
            let type = typeStr == "income" ? TransactionType.income : TransactionType.expense
            categories = categories.filter { $0.type == type }
        }

        return categories.map { cat in
            [
                "id": cat.id.uuidString,
                "name": cat.name,
                "icon": cat.icon,
                "color": cat.color,
                "type": cat.type == .income ? "income" : "expense",
                "isDefault": cat.isDefault
            ]
        }
    }

    private func addCategory(_ args: [String: Any]) async throws -> [String: Any] {
        guard let name = args["name"] as? String,
              let typeStr = args["type"] as? String else {
            throw FunctionToolError.invalidArguments("缺少必要参数: name, type")
        }

        let type = typeStr == "income" ? TransactionType.income : TransactionType.expense
        let icon = args["icon"] as? String ?? "tag"
        let color = args["color"] as? String ?? "gray"

        let category = Category(
            name: name,
            icon: icon,
            color: color,
            type: type,
            isDefault: false
        )

        modelContext.insert(category)
        try modelContext.save()

        return [
            "id": category.id.uuidString,
            "name": name,
            "message": "分类已添加"
        ]
    }

    private func updateCategory(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的分类ID")
        }

        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        guard let category = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("分类不存在")
        }

        if category.isDefault {
            throw FunctionToolError.unauthorized("不能修改默认分类")
        }

        if let name = args["name"] as? String {
            category.name = name
        }
        if let icon = args["icon"] as? String {
            category.icon = icon
        }
        if let color = args["color"] as? String {
            category.color = color
        }

        category.updatedAt = Date()
        try modelContext.save()

        return ["id": idStr, "message": "分类已更新"]
    }

    private func deleteCategory(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的分类ID")
        }

        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        guard let category = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("分类不存在")
        }

        if category.isDefault {
            throw FunctionToolError.unauthorized("不能删除默认分类")
        }

        modelContext.delete(category)
        try modelContext.save()

        return ["message": "分类已删除", "id": idStr]
    }
}

// MARK: - Member Tools

extension FunctionToolsService {
    private func listMembers() async throws -> [[String: Any]] {
        let members = try modelContext.fetch(FetchDescriptor<Member>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))

        let currentDefaultId = defaultMemberId

        return members.map { m in
            [
                "id": m.id.uuidString,
                "name": m.name,
                "nickname": m.nickname,
                "displayName": m.displayName,
                "role": m.role == .admin ? "admin" : "member",
                "avatarColor": m.avatarColor,
                "isDefault": m.id == currentDefaultId,
                "isCurrentUser": m.isCurrentUser
            ]
        }
    }

    private func addMember(_ args: [String: Any]) async throws -> [String: Any] {
        guard let name = args["name"] as? String else {
            throw FunctionToolError.invalidArguments("缺少必要参数: name")
        }

        let roleStr = args["role"] as? String ?? "member"
        let role = roleStr == "admin" ? MemberRole.admin : MemberRole.member

        let member = Member(
            name: name,
            nickname: args["nickname"] as? String ?? "",
            role: role,
            avatarColor: args["avatarColor"] as? String ?? "blue"
        )

        modelContext.insert(member)
        try modelContext.save()

        return [
            "id": member.id.uuidString,
            "name": name,
            "message": "成员已添加"
        ]
    }

    private func updateMember(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的成员ID")
        }

        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.id == id }
        )
        guard let member = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("成员不存在")
        }

        if let name = args["name"] as? String {
            member.name = name
        }
        if let nickname = args["nickname"] as? String {
            member.nickname = nickname
        }
        if let color = args["avatarColor"] as? String {
            member.avatarColor = color
        }

        member.updatedAt = Date()
        try modelContext.save()

        return ["id": idStr, "message": "成员已更新"]
    }

    private func deleteMember(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的成员ID")
        }

        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.id == id }
        )
        guard let member = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("成员不存在")
        }

        modelContext.delete(member)
        try modelContext.save()

        return ["message": "成员已删除", "id": idStr]
    }

    private func setDefaultMember(_ args: [String: Any]) async throws -> [String: Any] {
        var targetMember: Member?

        if let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) {
            let descriptor = FetchDescriptor<Member>(
                predicate: #Predicate { $0.id == id }
            )
            targetMember = try modelContext.fetch(descriptor).first
        } else if let name = args["name"] as? String {
            let descriptor = FetchDescriptor<Member>(
                predicate: #Predicate { $0.name == name || $0.nickname == name }
            )
            targetMember = try modelContext.fetch(descriptor).first
        }

        guard let member = targetMember else {
            throw FunctionToolError.notFound("成员不存在")
        }

        // 更新默认成员ID
        defaultMemberId = member.id

        return [
            "id": member.id.uuidString,
            "name": member.displayName,
            "message": "已设置为默认付款人"
        ]
    }
}

// MARK: - Report Tools

extension FunctionToolsService {
    private func getMonthlySummary(_ args: [String: Any]) async throws -> [String: Any] {
        let calendar = Calendar.current
        let now = Date()

        let year = args["year"] as? Int ?? calendar.component(.year, from: now)
        let month = args["month"] as? Int ?? calendar.component(.month, from: now)

        let (startDate, endDate) = getMonthDateRange(year: year, month: month)

        let transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>())
            .filter { $0.date >= startDate && $0.date < endDate }

        let totalIncome = transactions
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let totalExpense = transactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let balance = totalIncome - totalExpense

        return [
            "year": year,
            "month": month,
            "totalIncome": NSDecimalNumber(decimal: totalIncome).doubleValue,
            "totalExpense": NSDecimalNumber(decimal: totalExpense).doubleValue,
            "balance": NSDecimalNumber(decimal: balance).doubleValue,
            "transactionCount": transactions.count
        ]
    }

    private func getCategoryBreakdown(_ args: [String: Any]) async throws -> [[String: Any]] {
        let calendar = Calendar.current
        let now = Date()

        let year = args["year"] as? Int ?? calendar.component(.year, from: now)
        let month = args["month"] as? Int ?? calendar.component(.month, from: now)
        let typeStr = args["type"] as? String ?? "expense"
        let type = typeStr == "income" ? TransactionType.income : TransactionType.expense

        let (startDate, endDate) = getMonthDateRange(year: year, month: month)

        let transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>())
            .filter { $0.date >= startDate && $0.date < endDate && $0.type == type }

        let categories = try modelContext.fetch(FetchDescriptor<Category>())

        var breakdown: [UUID: Decimal] = [:]
        for tx in transactions {
            if let categoryId = tx.categoryId {
                breakdown[categoryId, default: .zero] += tx.amount
            }
        }

        let total = breakdown.values.reduce(Decimal.zero, +)

        return breakdown.map { (categoryId, amount) in
            let category = categories.first { $0.id == categoryId }
            let percentage = total > 0 ? (amount / total) * 100 : 0

            return [
                "categoryId": categoryId.uuidString,
                "categoryName": category?.name ?? "未分类",
                "categoryIcon": category?.icon ?? "tag",
                "amount": NSDecimalNumber(decimal: amount).doubleValue,
                "percentage": NSDecimalNumber(decimal: percentage).doubleValue
            ]
        }.sorted { ($0["amount"] as? Double ?? 0) > ($1["amount"] as? Double ?? 0) }
    }

    private func getMemberBreakdown(_ args: [String: Any]) async throws -> [[String: Any]] {
        let calendar = Calendar.current
        let now = Date()

        let year = args["year"] as? Int ?? calendar.component(.year, from: now)
        let month = args["month"] as? Int ?? calendar.component(.month, from: now)

        let (startDate, endDate) = getMonthDateRange(year: year, month: month)

        let transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>())
            .filter { $0.date >= startDate && $0.date < endDate && $0.type == .expense }

        let members = try modelContext.fetch(FetchDescriptor<Member>())

        var breakdown: [UUID: Decimal] = [:]
        for tx in transactions {
            if let payerId = tx.payerId {
                breakdown[payerId, default: .zero] += tx.amount
            }
        }

        let total = breakdown.values.reduce(Decimal.zero, +)

        return breakdown.map { (memberId, amount) in
            let member = members.first { $0.id == memberId }
            let percentage = total > 0 ? (amount / total) * 100 : 0

            return [
                "memberId": memberId.uuidString,
                "memberName": member?.displayName ?? "未知",
                "amount": NSDecimalNumber(decimal: amount).doubleValue,
                "percentage": NSDecimalNumber(decimal: percentage).doubleValue
            ]
        }.sorted { ($0["amount"] as? Double ?? 0) > ($1["amount"] as? Double ?? 0) }
    }
}

// MARK: - Reminder Tools

extension FunctionToolsService {
    private func listReminders() async throws -> [[String: Any]] {
        let reminders = try modelContext.fetch(FetchDescriptor<AccountingReminder>(
            sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute)]
        ))

        return reminders.map { r in
            [
                "id": r.id.uuidString,
                "hour": r.hour,
                "minute": r.minute,
                "time": r.timeString,
                "message": r.message,
                "frequency": r.frequency == .daily ? "daily" : "monthly",
                "isEnabled": r.isEnabled
            ]
        }
    }

    private func addReminder(_ args: [String: Any]) async throws -> [String: Any] {
        guard let hour = args["hour"] as? Int,
              let minute = args["minute"] as? Int else {
            throw FunctionToolError.invalidArguments("缺少必要参数: hour, minute")
        }

        let frequencyStr = args["frequency"] as? String ?? "daily"
        let frequency: ReminderFrequency = frequencyStr == "monthly" ? .monthly : .daily

        let reminder = AccountingReminder(
            hour: hour,
            minute: minute,
            message: args["message"] as? String ?? "别忘了记账哦~",
            frequency: frequency
        )

        modelContext.insert(reminder)
        try modelContext.save()

        // 调度通知
        let notificationService = NotificationService.shared
        await notificationService.scheduleReminder(reminder)

        return [
            "id": reminder.id.uuidString,
            "time": reminder.timeString,
            "message": "提醒已添加"
        ]
    }

    private func updateReminder(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的提醒ID")
        }

        let descriptor = FetchDescriptor<AccountingReminder>(
            predicate: #Predicate { $0.id == id }
        )
        guard let reminder = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("提醒不存在")
        }

        if let hour = args["hour"] as? Int {
            reminder.hour = hour
        }
        if let minute = args["minute"] as? Int {
            reminder.minute = minute
        }
        if let message = args["message"] as? String {
            reminder.message = message
        }
        if let isEnabled = args["isEnabled"] as? Bool {
            reminder.isEnabled = isEnabled
        }

        reminder.updatedAt = Date()
        try modelContext.save()

        // 更新通知
        let notificationService = NotificationService.shared
        await notificationService.updateSingleReminder(reminder)

        return ["id": idStr, "message": "提醒已更新"]
    }

    private func deleteReminder(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的提醒ID")
        }

        let descriptor = FetchDescriptor<AccountingReminder>(
            predicate: #Predicate { $0.id == id }
        )
        guard let reminder = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("提醒不存在")
        }

        // 取消通知
        let notificationService = NotificationService.shared
        notificationService.cancelReminder(reminder)

        modelContext.delete(reminder)
        try modelContext.save()

        return ["message": "提醒已删除", "id": idStr]
    }
}

// MARK: - Recurring Transaction Tools

extension FunctionToolsService {
    private func listRecurringTransactions() async throws -> [[String: Any]] {
        let recurring = try modelContext.fetch(FetchDescriptor<RecurringTransaction>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let members = try modelContext.fetch(FetchDescriptor<Member>())

        return recurring.map { r in
            let category = categories.first { $0.id == r.categoryId }
            let payer = members.first { $0.id == r.payerId }

            return [
                "id": r.id.uuidString,
                "name": r.name,
                "amount": NSDecimalNumber(decimal: r.amount).doubleValue,
                "type": r.type == .income ? "income" : "expense",
                "category": category?.name ?? "未分类",
                "frequency": r.frequency.rawValue,
                "weekday": r.weekday as Any,
                "dayOfMonth": r.dayOfMonth as Any,
                "payer": payer?.displayName ?? "",
                "isEnabled": r.isEnabled,
                "lastExecutedDate": r.lastExecutedDate.map { formatDate($0) } ?? ""
            ]
        }
    }

    private func addRecurringTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let name = args["name"] as? String,
              let amount = args["amount"] as? Double,
              let typeStr = args["type"] as? String,
              let categoryName = args["category"] as? String,
              let frequencyStr = args["frequency"] as? String else {
            throw FunctionToolError.invalidArguments("缺少必要参数")
        }

        let type = typeStr == "income" ? TransactionType.income : TransactionType.expense

        // 查找分类
        let categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == categoryName && $0.type == type }
        )
        guard let category = try modelContext.fetch(categoryDescriptor).first else {
            throw FunctionToolError.notFound("分类不存在: \(categoryName)")
        }

        let frequency: RecurringFrequency
        switch frequencyStr {
        case "daily": frequency = .daily
        case "weekly": frequency = .weekly
        case "monthly": frequency = .monthly
        case "yearly": frequency = .yearly
        default: frequency = .monthly
        }

        // 查找付款人
        var payerId: UUID?
        if let payerName = args["payer"] as? String {
            let memberDescriptor = FetchDescriptor<Member>(
                predicate: #Predicate { $0.name == payerName || $0.nickname == payerName }
            )
            payerId = try modelContext.fetch(memberDescriptor).first?.id
        }

        let recurring = RecurringTransaction(
            name: name,
            amount: Decimal(amount),
            type: type,
            categoryId: category.id,
            payerId: payerId,
            merchant: args["merchant"] as? String ?? "",
            frequency: frequency,
            interval: args["interval"] as? Int ?? 1,
            weekday: args["weekday"] as? Int,
            weekdays: args["weekdays"] as? [Int] ?? [],
            dayOfMonth: args["dayOfMonth"] as? Int,
            monthOfYear: args["monthOfYear"] as? Int,
            autoAdd: args["autoAdd"] as? Bool ?? false
        )

        modelContext.insert(recurring)
        try modelContext.save()

        return [
            "id": recurring.id.uuidString,
            "name": name,
            "message": "定期交易已创建"
        ]
    }

    private func updateRecurringTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的定期交易ID")
        }

        let descriptor = FetchDescriptor<RecurringTransaction>(
            predicate: #Predicate { $0.id == id }
        )
        guard let recurring = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("定期交易不存在")
        }

        if let name = args["name"] as? String {
            recurring.name = name
        }
        if let amount = args["amount"] as? Double {
            recurring.amount = Decimal(amount)
        }
        if let isEnabled = args["isEnabled"] as? Bool {
            recurring.isEnabled = isEnabled
        }

        try modelContext.save()

        return ["id": idStr, "message": "定期交易已更新"]
    }

    private func deleteRecurringTransaction(_ args: [String: Any]) async throws -> [String: Any] {
        guard let idStr = args["id"] as? String,
              let id = UUID(uuidString: idStr) else {
            throw FunctionToolError.invalidArguments("无效的定期交易ID")
        }

        let descriptor = FetchDescriptor<RecurringTransaction>(
            predicate: #Predicate { $0.id == id }
        )
        guard let recurring = try modelContext.fetch(descriptor).first else {
            throw FunctionToolError.notFound("定期交易不存在")
        }

        modelContext.delete(recurring)
        try modelContext.save()

        return ["message": "定期交易已删除", "id": idStr]
    }
}

// MARK: - Data Management Tools

extension FunctionToolsService {
    private func exportData(_ args: [String: Any]) async throws -> [String: Any] {
        let transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>())
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let members = try modelContext.fetch(FetchDescriptor<Member>())

        let count = transactions.count

        return [
            "format": "csv",
            "transactionCount": count,
            "categoryCount": categories.count,
            "memberCount": members.count,
            "message": "数据已准备好导出，共 \(count) 条交易记录"
        ]
    }

    private func getICloudStatus() async throws -> [String: Any] {
        let isAvailable = FileManager.default.ubiquityIdentityToken != nil

        var containerPath: String?
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            containerPath = containerURL.path
        }

        return [
            "isAvailable": isAvailable,
            "containerPath": containerPath ?? "",
            "message": isAvailable ? "iCloud 可用" : "iCloud 不可用"
        ]
    }

    private func syncData() async throws -> [String: Any] {
        // 触发同步
        await SyncService.shared.syncToiCloud(context: modelContext)

        return [
            "message": "同步已触发",
            "status": "syncing"
        ]
    }
}

// MARK: - Helpers

extension FunctionToolsService {
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private func getMonthDateRange(year: Int, month: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let startDate = calendar.date(from: components) ?? Date()
        let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date()

        return (startDate, endDate)
    }
}
