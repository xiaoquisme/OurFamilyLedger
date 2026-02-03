import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var categories: [Category]

    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @State private var showingFilters = false
    @State private var dateRange: ClosedRange<Date>?
    @State private var selectedType: TransactionType?

    init(filterType: TransactionType? = nil) {
        _selectedType = State(initialValue: filterType)
    }

    private func category(for transaction: TransactionRecord) -> Category? {
        guard let categoryId = transaction.categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    EmptyTransactionsView()
                } else {
                    transactionList
                }
            }
            .navigationTitle("明细")
            .searchable(text: $searchText, prompt: "搜索交易")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(
                    selectedCategory: $selectedCategory,
                    dateRange: $dateRange,
                    selectedType: $selectedType
                )
            }
        }
    }

    private var transactionList: some View {
        List {
            ForEach(groupedTransactions, id: \.key) { date, items in
                Section {
                    ForEach(items) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRowView(transaction: transaction, category: category(for: transaction))
                        }
                    }
                    .onDelete { indexSet in
                        deleteTransactions(items: items, at: indexSet)
                    }
                } header: {
                    HStack {
                        Text(formatSectionDate(date))
                        Spacer()
                        Text("¥\(daySummary(for: items))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: TransactionRecord.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
    }

    private var filteredTransactions: [TransactionRecord] {
        transactions.filter { transaction in
            // 搜索过滤
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                let matchesNote = transaction.note.lowercased().contains(searchLower)
                let matchesMerchant = transaction.merchant.lowercased().contains(searchLower)
                if !matchesNote && !matchesMerchant {
                    return false
                }
            }

            // 交易类型过滤
            if let type = selectedType {
                if transaction.type != type {
                    return false
                }
            }

            // 分类过滤
            if let category = selectedCategory {
                if transaction.categoryId != category.id {
                    return false
                }
            }

            // 日期范围过滤
            if let range = dateRange {
                if !range.contains(transaction.date) {
                    return false
                }
            }

            return true
        }
    }

    private var groupedTransactions: [(key: Date, value: [TransactionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func daySummary(for items: [TransactionRecord]) -> String {
        let total = items.reduce(Decimal(0)) { sum, transaction in
            switch transaction.type {
            case .expense: return sum - transaction.amount
            case .income: return sum + transaction.amount
            }
        }
        return String(format: "%.2f", NSDecimalNumber(decimal: total).doubleValue)
    }

    private func deleteTransactions(items: [TransactionRecord], at offsets: IndexSet) {
        for index in offsets {
            let transaction = items[index]
            modelContext.delete(transaction)
        }
    }
}

// MARK: - Transaction Row View

struct TransactionRowView: View {
    let transaction: TransactionRecord
    var category: Category?

    private var iconName: String {
        category?.icon ?? "tag"
    }

    private var iconColor: Color {
        guard let colorName = category?.color else { return .blue }
        switch colorName.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        case "brown": return .brown
        case "cyan": return .cyan
        case "mint": return .mint
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 分类图标
            Circle()
                .fill(iconColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(iconColor)
                }

            // 交易信息
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note.isEmpty ? "未分类" : transaction.note)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !transaction.merchant.isEmpty {
                        Text(transaction.merchant)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if transaction.participantIds.count > 1 {
                        Text("\(transaction.participantIds.count)人分摊")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // 金额
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(amountColor)

                if transaction.participantIds.count > 1 {
                    Text("每人 ¥\(splitAmountText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var amountText: String {
        let sign = transaction.type == .expense ? "-" : "+"
        return "\(sign)¥\(formattedAmount)"
    }

    private var amountColor: Color {
        transaction.type == .expense ? .primary : .green
    }

    private var formattedAmount: String {
        String(format: "%.2f", NSDecimalNumber(decimal: transaction.amount).doubleValue)
    }

    private var splitAmountText: String {
        let count = max(1, transaction.participantIds.count)
        let split = transaction.amount / Decimal(count)
        return String(format: "%.2f", NSDecimalNumber(decimal: split).doubleValue)
    }
}

// MARK: - Empty State View

struct EmptyTransactionsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("暂无交易记录", systemImage: "doc.text")
        } description: {
            Text("前往「记账」页面添加第一笔交易")
        }
    }
}

// MARK: - Filter View

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: Category?
    @Binding var dateRange: ClosedRange<Date>?
    @Binding var selectedType: TransactionType?

    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var useDateFilter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("交易类型") {
                    Picker("类型", selection: $selectedType) {
                        Text("全部").tag(nil as TransactionType?)
                        Text("支出").tag(TransactionType.expense as TransactionType?)
                        Text("收入").tag(TransactionType.income as TransactionType?)
                    }
                    .pickerStyle(.segmented)
                }

                Section("日期范围") {
                    Toggle("按日期筛选", isOn: $useDateFilter)

                    if useDateFilter {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section {
                    Button("清除筛选") {
                        selectedCategory = nil
                        dateRange = nil
                        selectedType = nil
                        useDateFilter = false
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyFilters()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyFilters() {
        if useDateFilter {
            dateRange = startDate...endDate
        } else {
            dateRange = nil
        }
    }
}

#Preview {
    TransactionListView()
}
