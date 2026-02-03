import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [TransactionRecord]

    @State private var selectedMonth = Date()
    @State private var selectedTab: ReportTab = .overview

    enum ReportTab: String, CaseIterable {
        case overview = "总览"
        case category = "分类"
        case member = "成员"
    }

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月份选择器
                MonthPicker(selectedMonth: $selectedMonth)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Tab 选择器
                Picker("报表类型", selection: $selectedTab) {
                    ForEach(ReportTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 内容区域
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .overview:
                            OverviewReport(transactions: monthlyTransactions)
                        case .category:
                            CategoryReport(transactions: monthlyTransactions)
                        case .member:
                            MemberReport(transactions: monthlyTransactions)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("报表")
        }
    }

    private var monthlyTransactions: [TransactionRecord] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: selectedMonth)
        let month = calendar.component(.month, from: selectedMonth)

        return transactions.filter { transaction in
            let transYear = calendar.component(.year, from: transaction.date)
            let transMonth = calendar.component(.month, from: transaction.date)
            return transYear == year && transMonth == month
        }
    }
}

// MARK: - Month Picker

struct MonthPicker: View {
    @Binding var selectedMonth: Date

    var body: some View {
        HStack {
            Button {
                selectedMonth = Calendar.current.date(
                    byAdding: .month,
                    value: -1,
                    to: selectedMonth
                ) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(monthText)
                .font(.headline)

            Spacer()

            Button {
                selectedMonth = Calendar.current.date(
                    byAdding: .month,
                    value: 1,
                    to: selectedMonth
                ) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
        }
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: selectedMonth)
    }
}

// MARK: - Overview Report

struct OverviewReport: View {
    let transactions: [TransactionRecord]

    var body: some View {
        VStack(spacing: 16) {
            // 收支卡片
            HStack(spacing: 16) {
                NavigationLink(destination: TransactionListView(filterType: .expense)) {
                    SummaryCard(
                        title: "支出",
                        amount: totalExpense,
                        color: .red,
                        icon: "arrow.up.circle.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: TransactionListView(filterType: .income)) {
                    SummaryCard(
                        title: "收入",
                        amount: totalIncome,
                        color: .green,
                        icon: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // 结余卡片
            VStack(spacing: 8) {
                Text("本月结余")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("¥\(formatAmount(balance))")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(balance >= 0 ? .green : .red)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // 日均支出
            if transactions.count > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Text("交易笔数")
                        Spacer()
                        Text("\(transactions.count) 笔")
                    }
                    HStack {
                        Text("日均支出")
                        Spacer()
                        Text("¥\(formatAmount(dailyAverageExpense))")
                    }
                }
                .font(.subheadline)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var totalExpense: Decimal {
        transactions
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var totalIncome: Decimal {
        transactions
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var balance: Decimal {
        totalIncome - totalExpense
    }

    private var dailyAverageExpense: Decimal {
        let calendar = Calendar.current
        let days = Set(transactions.map { calendar.startOfDay(for: $0.date) }).count
        guard days > 0 else { return 0 }
        return totalExpense / Decimal(days)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Text("¥\(formatAmount)")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var formatAmount: String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

// MARK: - Category Report

struct CategoryReport: View {
    let transactions: [TransactionRecord]
    @Query private var categories: [Category]

    init(transactions: [TransactionRecord]) {
        self.transactions = transactions
    }

    var body: some View {
        VStack(spacing: 16) {
            if categoryData.isEmpty {
                ContentUnavailableView(
                    "暂无数据",
                    systemImage: "chart.pie",
                    description: Text("本月还没有支出记录")
                )
            } else {
                // 饼图
                Chart(categoryData, id: \.category) { item in
                    SectorMark(
                        angle: .value("金额", NSDecimalNumber(decimal: item.amount).doubleValue),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(by: .value("分类", item.category))
                }
                .frame(height: 200)

                // 分类列表
                VStack(spacing: 12) {
                    ForEach(categoryData.sorted { $0.amount > $1.amount }, id: \.category) { item in
                        HStack {
                            Circle()
                                .fill(item.color)
                                .frame(width: 12, height: 12)

                            Text(item.category)

                            Spacer()

                            Text("¥\(formatAmount(item.amount))")
                                .fontWeight(.medium)

                            Text("\(Int(item.percentage))%")
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var categoryData: [CategoryAmount] {
        let expenses = transactions.filter { $0.type == .expense }
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }

        let grouped = Dictionary(grouping: expenses) { $0.categoryId }

        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .yellow, .teal]
        var colorIndex = 0

        return grouped.compactMap { categoryId, items -> CategoryAmount? in
            let amount = items.reduce(Decimal(0)) { $0 + $1.amount }
            let percentage = total > 0 ? (amount / total * 100) : 0

            // 查找分类名称
            let categoryName: String
            if let id = categoryId,
               let category = categories.first(where: { $0.id == id }) {
                categoryName = category.name
            } else {
                categoryName = items.first?.note.isEmpty == false ? items.first!.note : "未分类"
            }

            let color = colors[colorIndex % colors.count]
            colorIndex += 1

            return CategoryAmount(
                category: categoryName,
                amount: amount,
                percentage: NSDecimalNumber(decimal: percentage).doubleValue,
                color: color
            )
        }
    }

    private func formatAmount(_ amount: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

struct CategoryAmount {
    let category: String
    let amount: Decimal
    let percentage: Double
    var color: Color = .blue
}

// MARK: - Member Report

struct MemberReport: View {
    let transactions: [TransactionRecord]
    @Query private var members: [Member]

    init(transactions: [TransactionRecord]) {
        self.transactions = transactions
    }

    var body: some View {
        VStack(spacing: 16) {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "暂无数据",
                    systemImage: "person.3",
                    description: Text("本月还没有交易记录")
                )
            } else {
                // 成员支付统计
                VStack(alignment: .leading, spacing: 12) {
                    Text("成员支付")
                        .font(.headline)

                    Text("各成员实际支付的金额")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(memberPaymentData, id: \.memberId) { data in
                        MemberStatRow(
                            name: data.name,
                            amount: data.paidAmount,
                            color: data.color,
                            label: "支付"
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 成员分摊统计
                VStack(alignment: .leading, spacing: 12) {
                    Text("成员分摊")
                        .font(.headline)

                    Text("根据参与情况计算每人应分摊金额")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(memberShareData, id: \.memberId) { data in
                        MemberStatRow(
                            name: data.name,
                            amount: data.shareAmount,
                            color: data.color,
                            label: "分摊"
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 结算情况
                VStack(alignment: .leading, spacing: 12) {
                    Text("结算情况")
                        .font(.headline)

                    Text("正数表示该成员多付了钱，负数表示还需支付")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(settlementData, id: \.memberId) { data in
                        HStack {
                            Text(data.name)
                            Spacer()
                            Text(data.balance >= 0 ? "+¥\(formatAmount(data.balance))" : "-¥\(formatAmount(abs(data.balance)))")
                                .fontWeight(.medium)
                                .foregroundStyle(data.balance >= 0 ? .green : .red)
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var memberPaymentData: [MemberStat] {
        let expenses = transactions.filter { $0.type == .expense }
        var paymentByMember: [UUID: Decimal] = [:]

        for transaction in expenses {
            if let payerId = transaction.payerId {
                paymentByMember[payerId, default: 0] += transaction.amount
            }
        }

        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .yellow, .teal]

        return paymentByMember.enumerated().map { index, item in
            let memberName = members.first(where: { $0.id == item.key })?.displayName ?? "未知"
            return MemberStat(
                memberId: item.key,
                name: memberName,
                paidAmount: item.value,
                shareAmount: 0,
                color: colors[index % colors.count]
            )
        }.sorted { $0.paidAmount > $1.paidAmount }
    }

    private var memberShareData: [MemberStat] {
        let expenses = transactions.filter { $0.type == .expense }
        var shareByMember: [UUID: Decimal] = [:]

        for transaction in expenses {
            let participantCount = max(1, transaction.participantIds.count)
            let shareAmount = transaction.amount / Decimal(participantCount)

            for participantId in transaction.participantIds {
                shareByMember[participantId, default: 0] += shareAmount
            }
        }

        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .yellow, .teal]

        return shareByMember.enumerated().map { index, item in
            let memberName = members.first(where: { $0.id == item.key })?.displayName ?? "未知"
            return MemberStat(
                memberId: item.key,
                name: memberName,
                paidAmount: 0,
                shareAmount: item.value,
                color: colors[index % colors.count]
            )
        }.sorted { $0.shareAmount > $1.shareAmount }
    }

    private var settlementData: [MemberStat] {
        let paymentData = Dictionary(uniqueKeysWithValues: memberPaymentData.map { ($0.memberId, $0.paidAmount) })
        let shareData = Dictionary(uniqueKeysWithValues: memberShareData.map { ($0.memberId, $0.shareAmount) })

        let allMemberIds = Set(paymentData.keys).union(Set(shareData.keys))

        return allMemberIds.map { memberId in
            let paid = paymentData[memberId] ?? 0
            let share = shareData[memberId] ?? 0
            let balance = paid - share
            let memberName = members.first(where: { $0.id == memberId })?.displayName ?? "未知"

            return MemberStat(
                memberId: memberId,
                name: memberName,
                paidAmount: paid,
                shareAmount: share,
                balance: balance,
                color: .blue
            )
        }.sorted { $0.balance > $1.balance }
    }

    private func formatAmount(_ amount: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

struct MemberStat {
    let memberId: UUID
    let name: String
    let paidAmount: Decimal
    let shareAmount: Decimal
    var balance: Decimal = 0
    let color: Color
}

struct MemberStatRow: View {
    let name: String
    let amount: Decimal
    let color: Color
    let label: String

    var body: some View {
        HStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(color)
                }

            Text(name)

            Spacer()

            Text("¥\(formatAmount(amount))")
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

#Preview {
    ReportsView()
}
