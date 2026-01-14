import SwiftUI
import SwiftData

// MARK: - 定期交易列表

struct RecurringTransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringTransaction.createdAt, order: .reverse) private var recurringTransactions: [RecurringTransaction]

    @State private var showingAddSheet = false

    var body: some View {
        List {
            if recurringTransactions.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("暂无定期交易")
                            .font(.headline)

                        Text("添加定期交易后，每次打开 App 会自动提醒你记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ForEach(recurringTransactions) { recurring in
                    NavigationLink {
                        EditRecurringTransactionView(recurring: recurring)
                    } label: {
                        RecurringTransactionRow(recurring: recurring)
                    }
                }
                .onDelete(perform: deleteRecurring)
            }

            Section {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("添加定期交易", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("定期交易")
        .sheet(isPresented: $showingAddSheet) {
            AddRecurringTransactionView()
        }
    }

    private func deleteRecurring(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(recurringTransactions[index])
        }
    }
}

// MARK: - 定期交易行

struct RecurringTransactionRow: View {
    let recurring: RecurringTransaction
    @Query private var categories: [Category]

    var categoryName: String {
        guard let categoryId = recurring.categoryId else { return "" }
        return categories.first { $0.id == categoryId }?.name ?? ""
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recurring.name)
                        .fontWeight(.medium)

                    if !recurring.isEnabled {
                        Text("已暂停")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(recurring.frequency.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())

                    if !categoryName.isEmpty {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text("¥\(NSDecimalNumber(decimal: recurring.amount).doubleValue, specifier: "%.2f")")
                .font(.headline)
                .foregroundStyle(recurring.type == .expense ? .red : .green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 添加定期交易

struct AddRecurringTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [Category]
    @Query private var members: [Member]

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: TransactionType = .expense
    @State private var frequency: RecurringFrequency = .daily
    @State private var selectedCategoryId: UUID?
    @State private var selectedPayerId: UUID?
    @State private var merchant = ""
    @State private var weekday = 1 // 周一
    @State private var dayOfMonth = 1

    private var filteredCategories: [Category] {
        categories.filter { $0.type == type }
    }

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（如：通勤交通费）", text: $name)

                    HStack {
                        Text("¥")
                        TextField("金额", text: $amountText)
                            .keyboardType(.decimalPad)
                    }

                    Picker("类型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .onChange(of: type) { _, _ in
                        selectedCategoryId = nil
                    }
                }

                Section("分类") {
                    if filteredCategories.isEmpty {
                        Text("暂无分类")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("分类", selection: $selectedCategoryId) {
                            Text("不选择").tag(nil as UUID?)
                            ForEach(filteredCategories) { category in
                                Text(category.name).tag(category.id as UUID?)
                            }
                        }
                    }
                }

                Section("付款人") {
                    Picker("付款人", selection: $selectedPayerId) {
                        Text("不选择").tag(nil as UUID?)
                        ForEach(members) { member in
                            Text(member.name).tag(member.id as UUID?)
                        }
                    }
                }

                Section("重复周期") {
                    Picker("频率", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    if frequency == .weekly {
                        Picker("每周几", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { day in
                                Text(weekdays[day]).tag(day)
                            }
                        }
                    }

                    if frequency == .monthly {
                        Picker("每月几号", selection: $dayOfMonth) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)号").tag(day)
                            }
                        }
                    }
                }

                Section("其他") {
                    TextField("商户（可选）", text: $merchant)
                }
            }
            .navigationTitle("添加定期交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addRecurring()
                    }
                    .disabled(name.isEmpty || amountText.isEmpty)
                }
            }
        }
    }

    private func addRecurring() {
        guard let amount = Decimal(string: amountText) else { return }

        let recurring = RecurringTransaction(
            name: name,
            amount: amount,
            type: type,
            categoryId: selectedCategoryId,
            payerId: selectedPayerId,
            merchant: merchant,
            frequency: frequency,
            weekday: frequency == .weekly ? weekday : nil,
            dayOfMonth: frequency == .monthly ? dayOfMonth : nil
        )

        modelContext.insert(recurring)
        dismiss()
    }
}

// MARK: - 编辑定期交易

struct EditRecurringTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [Category]
    @Query private var members: [Member]

    @Bindable var recurring: RecurringTransaction

    @State private var amountText = ""

    private var filteredCategories: [Category] {
        categories.filter { $0.type == recurring.type }
    }

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $recurring.name)

                HStack {
                    Text("¥")
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                        .onChange(of: amountText) { _, newValue in
                            if let amount = Decimal(string: newValue) {
                                recurring.amount = amount
                            }
                        }
                }

                Picker("类型", selection: $recurring.type) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }

                Toggle("启用", isOn: $recurring.isEnabled)
            }

            Section("分类") {
                Picker("分类", selection: $recurring.categoryId) {
                    Text("不选择").tag(nil as UUID?)
                    ForEach(filteredCategories) { category in
                        Text(category.name).tag(category.id as UUID?)
                    }
                }
            }

            Section("付款人") {
                Picker("付款人", selection: $recurring.payerId) {
                    Text("不选择").tag(nil as UUID?)
                    ForEach(members) { member in
                        Text(member.name).tag(member.id as UUID?)
                    }
                }
            }

            Section("重复周期") {
                Picker("频率", selection: $recurring.frequency) {
                    ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }

                if recurring.frequency == .weekly {
                    Picker("每周几", selection: Binding(
                        get: { recurring.weekday ?? 1 },
                        set: { recurring.weekday = $0 }
                    )) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(weekdays[day]).tag(day)
                        }
                    }
                }

                if recurring.frequency == .monthly {
                    Picker("每月几号", selection: Binding(
                        get: { recurring.dayOfMonth ?? 1 },
                        set: { recurring.dayOfMonth = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)号").tag(day)
                        }
                    }
                }
            }

            Section("其他") {
                TextField("商户（可选）", text: $recurring.merchant)

                if let lastDate = recurring.lastExecutedDate {
                    HStack {
                        Text("上次记录")
                        Spacer()
                        Text(lastDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("编辑定期交易")
        .onAppear {
            amountText = "\(recurring.amount)"
        }
    }
}

#Preview {
    NavigationStack {
        RecurringTransactionListView()
    }
}
