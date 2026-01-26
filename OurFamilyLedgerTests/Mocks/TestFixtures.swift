import Foundation
@testable import OurFamilyLedger

/// Test fixtures for creating sample data
enum TestFixtures {
    // MARK: - TransactionDraft Fixtures

    static func transactionDraft(
        id: UUID = UUID(),
        date: Date = Date(),
        amount: Decimal = 100,
        type: TransactionType = .expense,
        categoryName: String = "餐饮",
        payerName: String = "测试用户",
        participantNames: [String]? = nil,
        note: String = "",
        merchant: String = "",
        source: TransactionSource = .manual,
        ocrText: String? = nil
    ) -> TransactionDraft {
        TransactionDraft(
            id: id,
            date: date,
            amount: amount,
            type: type,
            categoryName: categoryName,
            payerName: payerName,
            participantNames: participantNames ?? [payerName],
            note: note,
            merchant: merchant,
            source: source,
            ocrText: ocrText
        )
    }

    // MARK: - Member Fixtures

    static func member(
        id: UUID = UUID(),
        name: String = "测试用户",
        nickname: String = "",
        role: MemberRole = .member,
        avatarColor: String = "blue",
        isCurrentUser: Bool = false
    ) -> Member {
        Member(
            id: id,
            name: name,
            nickname: nickname,
            role: role,
            avatarColor: avatarColor,
            isCurrentUser: isCurrentUser
        )
    }

    // MARK: - Category Fixtures

    static func category(
        id: UUID = UUID(),
        name: String = "餐饮",
        icon: String = "fork.knife",
        color: String = "gray",
        type: TransactionType = .expense,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) -> OurFamilyLedger.Category {
        OurFamilyLedger.Category(
            id: id,
            name: name,
            icon: icon,
            color: color,
            type: type,
            isDefault: isDefault,
            sortOrder: sortOrder
        )
    }

    // MARK: - TransactionRecord Fixtures

    static func transactionRecord(
        id: UUID = UUID(),
        date: Date = Date(),
        amount: Decimal = 100,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        payerId: UUID? = nil,
        participantIds: [UUID] = [],
        note: String = "",
        merchant: String = "",
        source: TransactionSource = .manual
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            date: date,
            amount: amount,
            type: type,
            categoryId: categoryId,
            payerId: payerId,
            participantIds: participantIds,
            note: note,
            merchant: merchant,
            source: source
        )
    }

    // MARK: - AccountingReminder Fixtures

    static func accountingReminder(
        id: UUID = UUID(),
        hour: Int = 14,
        minute: Int = 0,
        message: String = "记账时间到了，赶紧记一笔吧！",
        frequency: ReminderFrequency = .daily,
        isEnabled: Bool = true
    ) -> AccountingReminder {
        AccountingReminder(
            id: id,
            hour: hour,
            minute: minute,
            message: message,
            frequency: frequency,
            isEnabled: isEnabled
        )
    }

    // MARK: - RecurringTransaction Fixtures

    static func recurringTransaction(
        name: String = "日常开支",
        amount: Decimal = 50,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        payerId: UUID? = nil,
        frequency: RecurringFrequency = .daily
    ) -> RecurringTransaction {
        RecurringTransaction(
            name: name,
            amount: amount,
            type: type,
            categoryId: categoryId,
            payerId: payerId,
            frequency: frequency
        )
    }

    // MARK: - Sample Data Sets

    static var sampleMembers: [Member] {
        [
            member(name: "爸爸", nickname: "老爸", role: .admin),
            member(name: "妈妈", nickname: "老妈"),
            member(name: "儿子", nickname: "小宝")
        ]
    }

    static var sampleCategories: [OurFamilyLedger.Category] {
        [
            category(name: "餐饮", icon: "fork.knife", sortOrder: 0),
            category(name: "购物", icon: "bag", sortOrder: 1),
            category(name: "交通", icon: "bus", sortOrder: 2),
            category(name: "工资", icon: "yensign.square", type: .income, sortOrder: 0)
        ]
    }

    static var sampleTransactionDrafts: [TransactionDraft] {
        [
            transactionDraft(amount: 50, categoryName: "餐饮", payerName: "爸爸"),
            transactionDraft(amount: 200, categoryName: "购物", payerName: "妈妈"),
            transactionDraft(amount: 30, categoryName: "交通", payerName: "爸爸")
        ]
    }
}
