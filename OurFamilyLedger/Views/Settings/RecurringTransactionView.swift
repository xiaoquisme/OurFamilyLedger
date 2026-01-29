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

                    if recurring.autoAdd {
                        Text("自动")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }

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
                    Text(recurring.recurrenceDescription)
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
    @State private var interval = 1
    @State private var selectedCategoryId: UUID?
    @State private var selectedPayerId: UUID?
    @State private var merchant = ""
    @State private var weekday = 1 // 周一
    @State private var selectedWeekdays: Set<Int> = []
    @State private var dayOfMonth = 1
    @State private var monthOfYear = 1
    @State private var autoAdd = false
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var hasOccurrenceLimit = false
    @State private var occurrenceCount = 10

    private var filteredCategories: [Category] {
        categories.filter { $0.type == type }
    }

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private let months = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]

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

                    Stepper("间隔: \(interval) \(frequencyUnit)", value: $interval, in: 1...99)

                    if frequency == .weekly {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("每周几")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                ForEach(0..<7, id: \.self) { day in
                                    Button {
                                        if selectedWeekdays.contains(day) {
                                            selectedWeekdays.remove(day)
                                        } else {
                                            selectedWeekdays.insert(day)
                                        }
                                    } label: {
                                        Text(weekdays[day])
                                            .font(.caption)
                                            .frame(width: 40, height: 40)
                                            .background(selectedWeekdays.contains(day) ? Color.blue : Color.gray.opacity(0.2))
                                            .foregroundStyle(selectedWeekdays.contains(day) ? .white : .primary)
                                            .clipShape(Circle())
                                    }
                                }
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

                    if frequency == .yearly {
                        Picker("月份", selection: $monthOfYear) {
                            ForEach(1...12, id: \.self) { month in
                                Text(months[month - 1]).tag(month)
                            }
                        }
                        
                        Picker("日期", selection: $dayOfMonth) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)号").tag(day)
                            }
                        }
                    }
                }

                Section("结束条件") {
                    Toggle("设置结束日期", isOn: $hasEndDate)
                    
                    if hasEndDate {
                        DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    }
                    
                    Toggle("限制重复次数", isOn: $hasOccurrenceLimit)
                    
                    if hasOccurrenceLimit {
                        Stepper("重复 \(occurrenceCount) 次", value: $occurrenceCount, in: 1...999)
                    }
                }

                Section {
                    Toggle("自动添加", isOn: $autoAdd)
                    
                    if autoAdd {
                        Text("开启后，将在每个周期自动创建交易记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("开启后，将在每个周期提醒您手动确认")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("添加方式")
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
                    .disabled(name.isEmpty || amountText.isEmpty || !isValidConfiguration)
                }
            }
        }
    }

    private var frequencyUnit: String {
        switch frequency {
        case .daily: return "天"
        case .weekly: return "周"
        case .monthly: return "月"
        case .yearly: return "年"
        }
    }

    private var isValidConfiguration: Bool {
        switch frequency {
        case .weekly:
            return !selectedWeekdays.isEmpty
        case .monthly, .yearly:
            return true
        case .daily:
            return true
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
            interval: interval,
            weekday: selectedWeekdays.first,
            weekdays: Array(selectedWeekdays),
            dayOfMonth: (frequency == .monthly || frequency == .yearly) ? dayOfMonth : nil,
            monthOfYear: frequency == .yearly ? monthOfYear : nil,
            autoAdd: autoAdd,
            endDate: hasEndDate ? endDate : nil,
            occurrenceCount: hasOccurrenceLimit ? occurrenceCount : nil
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
    @State private var selectedWeekdays: Set<Int> = []

    private var filteredCategories: [Category] {
        categories.filter { $0.type == recurring.type }
    }

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private let months = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]

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

                Stepper("间隔: \(recurring.interval) \(frequencyUnit)", value: $recurring.interval, in: 1...99)

                if recurring.frequency == .weekly {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每周几")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            ForEach(0..<7, id: \.self) { day in
                                Button {
                                    if selectedWeekdays.contains(day) {
                                        selectedWeekdays.remove(day)
                                    } else {
                                        selectedWeekdays.insert(day)
                                    }
                                    recurring.weekdays = Array(selectedWeekdays)
                                } label: {
                                    Text(weekdays[day])
                                        .font(.caption)
                                        .frame(width: 40, height: 40)
                                        .background(selectedWeekdays.contains(day) ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundStyle(selectedWeekdays.contains(day) ? .white : .primary)
                                        .clipShape(Circle())
                                }
                            }
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

                if recurring.frequency == .yearly {
                    Picker("月份", selection: Binding(
                        get: { recurring.monthOfYear ?? 1 },
                        set: { recurring.monthOfYear = $0 }
                    )) {
                        ForEach(1...12, id: \.self) { month in
                            Text(months[month - 1]).tag(month)
                        }
                    }
                    
                    Picker("日期", selection: Binding(
                        get: { recurring.dayOfMonth ?? 1 },
                        set: { recurring.dayOfMonth = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)号").tag(day)
                        }
                    }
                }
            }

            Section("结束条件") {
                Toggle("设置结束日期", isOn: Binding(
                    get: { recurring.endDate != nil },
                    set: { newValue in
                        if newValue {
                            recurring.endDate = Date()
                        } else {
                            recurring.endDate = nil
                        }
                    }
                ))
                
                if recurring.endDate != nil {
                    DatePicker("结束日期", selection: Binding(
                        get: { recurring.endDate ?? Date() },
                        set: { recurring.endDate = $0 }
                    ), displayedComponents: .date)
                }
                
                Toggle("限制重复次数", isOn: Binding(
                    get: { recurring.occurrenceCount != nil },
                    set: { newValue in
                        if newValue {
                            recurring.occurrenceCount = 10
                        } else {
                            recurring.occurrenceCount = nil
                        }
                    }
                ))
                
                if recurring.occurrenceCount != nil {
                    Stepper("重复 \(recurring.occurrenceCount ?? 10) 次", value: Binding(
                        get: { recurring.occurrenceCount ?? 10 },
                        set: { recurring.occurrenceCount = $0 }
                    ), in: 1...999)
                }
            }

            Section {
                Toggle("自动添加", isOn: $recurring.autoAdd)
                
                if recurring.autoAdd {
                    Text("开启后，将在每个周期自动创建交易记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("关闭后，将在每个周期提醒您手动确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("添加方式")
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

                HStack {
                    Text("已执行次数")
                    Spacer()
                    Text("\(recurring.executedCount)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("编辑定期交易")
        .onAppear {
            amountText = "\(recurring.amount)"
            selectedWeekdays = Set(recurring.weekdays)
        }
    }

    private var frequencyUnit: String {
        switch recurring.frequency {
        case .daily: return "天"
        case .weekly: return "周"
        case .monthly: return "月"
        case .yearly: return "年"
        }
    }
}

#Preview {
    NavigationStack {
        RecurringTransactionListView()
    }
}
