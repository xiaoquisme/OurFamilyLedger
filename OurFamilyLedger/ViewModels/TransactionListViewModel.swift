import Foundation
import SwiftUI
import SwiftData

/// 交易列表筛选条件
struct TransactionFilter {
    var startDate: Date?
    var endDate: Date?
    var categoryIds: Set<UUID> = []
    var payerIds: Set<UUID> = []
    var participantIds: Set<UUID> = []
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var searchText: String = ""
    var types: Set<TransactionType> = []

    var isActive: Bool {
        startDate != nil ||
        endDate != nil ||
        !categoryIds.isEmpty ||
        !payerIds.isEmpty ||
        !participantIds.isEmpty ||
        minAmount != nil ||
        maxAmount != nil ||
        !searchText.isEmpty ||
        !types.isEmpty
    }

    mutating func reset() {
        startDate = nil
        endDate = nil
        categoryIds.removeAll()
        payerIds.removeAll()
        participantIds.removeAll()
        minAmount = nil
        maxAmount = nil
        searchText = ""
        types.removeAll()
    }
}

/// 交易列表 ViewModel
@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var filter = TransactionFilter()
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var selectedTransactions: Set<UUID> = []
    @Published var isMultiSelectMode = false

    enum SortOrder: String, CaseIterable {
        case dateDescending = "日期（新到旧）"
        case dateAscending = "日期（旧到新）"
        case amountDescending = "金额（高到低）"
        case amountAscending = "金额（低到高）"
    }

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Filtering

    /// 应用筛选条件
    func applyFilter(to transactions: [TransactionRecord]) -> [TransactionRecord] {
        var result = transactions

        // 日期范围
        if let startDate = filter.startDate {
            result = result.filter { $0.date >= startDate }
        }
        if let endDate = filter.endDate {
            result = result.filter { $0.date <= endDate }
        }

        // 分类
        if !filter.categoryIds.isEmpty {
            result = result.filter { transaction in
                guard let categoryId = transaction.categoryId else { return false }
                return filter.categoryIds.contains(categoryId)
            }
        }

        // 付款人
        if !filter.payerIds.isEmpty {
            result = result.filter { transaction in
                guard let payerId = transaction.payerId else { return false }
                return filter.payerIds.contains(payerId)
            }
        }

        // 参与人
        if !filter.participantIds.isEmpty {
            result = result.filter { transaction in
                !Set(transaction.participantIds).isDisjoint(with: filter.participantIds)
            }
        }

        // 金额范围
        if let minAmount = filter.minAmount {
            result = result.filter { $0.amount >= minAmount }
        }
        if let maxAmount = filter.maxAmount {
            result = result.filter { $0.amount <= maxAmount }
        }

        // 类型
        if !filter.types.isEmpty {
            result = result.filter { filter.types.contains($0.type) }
        }

        // 搜索文本
        if !filter.searchText.isEmpty {
            let searchLower = filter.searchText.lowercased()
            result = result.filter { transaction in
                transaction.note.lowercased().contains(searchLower) ||
                transaction.merchant.lowercased().contains(searchLower)
            }
        }

        return result
    }

    // MARK: - Sorting

    /// 应用排序
    func applySort(to transactions: [TransactionRecord]) -> [TransactionRecord] {
        switch sortOrder {
        case .dateDescending:
            return transactions.sorted { $0.date > $1.date }
        case .dateAscending:
            return transactions.sorted { $0.date < $1.date }
        case .amountDescending:
            return transactions.sorted { $0.amount > $1.amount }
        case .amountAscending:
            return transactions.sorted { $0.amount < $1.amount }
        }
    }

    // MARK: - Grouping

    /// 按日期分组
    func groupByDate(_ transactions: [TransactionRecord]) -> [(date: Date, transactions: [TransactionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, transactions: $0.value) }
    }

    /// 按月份分组
    func groupByMonth(_ transactions: [TransactionRecord]) -> [(month: Date, transactions: [TransactionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (month: $0.key, transactions: $0.value) }
    }

    // MARK: - Statistics

    /// 计算日总计
    func daySummary(for transactions: [TransactionRecord]) -> (expense: Decimal, income: Decimal, balance: Decimal) {
        var expense: Decimal = 0
        var income: Decimal = 0

        for transaction in transactions {
            switch transaction.type {
            case .expense:
                expense += transaction.amount
            case .income:
                income += transaction.amount
            }
        }

        return (expense, income, income - expense)
    }

    // MARK: - Multi-Select Operations

    /// 切换多选模式
    func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedTransactions.removeAll()
        }
    }

    /// 选择/取消选择交易
    func toggleSelection(for transactionId: UUID) {
        if selectedTransactions.contains(transactionId) {
            selectedTransactions.remove(transactionId)
        } else {
            selectedTransactions.insert(transactionId)
        }
    }

    /// 全选
    func selectAll(_ transactions: [TransactionRecord]) {
        selectedTransactions = Set(transactions.map { $0.id })
    }

    /// 取消全选
    func deselectAll() {
        selectedTransactions.removeAll()
    }

    /// 批量删除选中的交易
    func deleteSelected() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<TransactionRecord>()
        guard let allTransactions = try? modelContext.fetch(descriptor) else { return }

        for transaction in allTransactions {
            if selectedTransactions.contains(transaction.id) {
                modelContext.delete(transaction)
            }
        }

        selectedTransactions.removeAll()
        isMultiSelectMode = false
    }

    // MARK: - Duplicate

    /// 复制交易（快速创建相似交易）
    func duplicateTransaction(_ transaction: TransactionRecord) {
        guard let modelContext = modelContext else { return }

        let newTransaction = TransactionRecord(
            date: Date(),
            amount: transaction.amount,
            type: transaction.type,
            categoryId: transaction.categoryId,
            payerId: transaction.payerId,
            participantIds: transaction.participantIds,
            note: transaction.note,
            merchant: transaction.merchant,
            source: .manual
        )

        modelContext.insert(newTransaction)
    }
}
