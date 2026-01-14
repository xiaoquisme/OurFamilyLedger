import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("accountingReminder") private var accountingReminder = "off"

    @State private var selectedTab: Tab = .chat
    @State private var hasSynced = false
    @State private var hasCheckedReminder = false
    @State private var hasCheckedRecurringToday = false

    // 通用记账提醒
    @State private var showingReminder = false
    @State private var reminderMessage = ""

    // 定期交易提醒
    @State private var pendingRecurringTransactions: [RecurringTransaction] = []
    @State private var showingRecurringConfirmation = false

    enum Tab: String, CaseIterable {
        case chat = "记账"
        case transactions = "明细"
        case reports = "报表"
        case family = "家庭"
        case settings = "设置"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.text.bubble.right"
            case .transactions: return "list.bullet.rectangle"
            case .reports: return "chart.pie"
            case .family: return "person.3"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label(Tab.chat.rawValue, systemImage: Tab.chat.icon)
                }
                .tag(Tab.chat)

            TransactionListView()
                .tabItem {
                    Label(Tab.transactions.rawValue, systemImage: Tab.transactions.icon)
                }
                .tag(Tab.transactions)

            ReportsView()
                .tabItem {
                    Label(Tab.reports.rawValue, systemImage: Tab.reports.icon)
                }
                .tag(Tab.reports)

            FamilyView()
                .tabItem {
                    Label(Tab.family.rawValue, systemImage: Tab.family.icon)
                }
                .tag(Tab.family)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .task {
            // App 启动时从 iCloud 加载数据
            guard !hasSynced else { return }
            hasSynced = true
            await SyncService.shared.loadFromiCloud(context: modelContext)

            // 检查定期交易
            checkRecurringTransactions()

            // 检查通用记账提醒
            checkAccountingReminder()
        }
        .alert("记账提醒", isPresented: $showingReminder) {
            Button("去记账") {
                selectedTab = .chat
            }
            Button("稍后再说", role: .cancel) {}
        } message: {
            Text(reminderMessage)
        }
        .sheet(isPresented: $showingRecurringConfirmation) {
            RecurringTransactionConfirmationView(
                pendingTransactions: pendingRecurringTransactions,
                onConfirm: { transactions in
                    confirmRecurringTransactions(transactions)
                },
                onDismiss: {
                    showingRecurringConfirmation = false
                }
            )
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            #if DEBUG
            print("🔄 scenePhase changed: \(oldPhase) -> \(newPhase)")
            #endif
            if newPhase == .active {
                // App 进入前台时检查定期交易
                #if DEBUG
                print("📱 App 进入前台，检查定期交易...")
                #endif
                checkRecurringTransactions()
            }
        }
    }

    // MARK: - 定期交易检查

    private func checkRecurringTransactions() {
        // 如果弹窗已经在显示，不重复检查
        guard !showingRecurringConfirmation else { return }

        do {
            let descriptor = FetchDescriptor<RecurringTransaction>(
                predicate: #Predicate<RecurringTransaction> { $0.isEnabled == true }
            )
            let allRecurring = try modelContext.fetch(descriptor)

            #if DEBUG
            print("📋 定期交易检查: 找到 \(allRecurring.count) 个启用的定期交易")
            for recurring in allRecurring {
                print("  - \(recurring.name): frequency=\(recurring.frequency.rawValue), dayOfMonth=\(recurring.dayOfMonth ?? -1), shouldExecute=\(recurring.shouldExecuteToday())")
            }
            #endif

            // 找出今天应该执行的定期交易
            pendingRecurringTransactions = allRecurring.filter { $0.shouldExecuteToday() }

            if !pendingRecurringTransactions.isEmpty {
                showingRecurringConfirmation = true
            }
        } catch {
            print("检查定期交易失败: \(error)")
        }
    }

    private func confirmRecurringTransactions(_ transactions: [RecurringTransaction]) {
        let today = Date()

        for recurring in transactions {
            // 创建交易记录
            let transaction = TransactionRecord(
                date: today,
                amount: recurring.amount,
                type: recurring.type,
                categoryId: recurring.categoryId,
                payerId: recurring.payerId,
                participantIds: recurring.participantIds,
                note: recurring.name,
                merchant: recurring.merchant,
                source: .manual
            )

            modelContext.insert(transaction)

            // 更新上次执行日期
            recurring.lastExecutedDate = today
        }

        try? modelContext.save()
        showingRecurringConfirmation = false
    }

    // MARK: - 通用记账提醒检查

    private func checkAccountingReminder() {
        guard !hasCheckedReminder else { return }
        hasCheckedReminder = true

        guard accountingReminder != "off" else { return }

        // 如果已经有定期交易弹窗，先不显示通用提醒
        guard !showingRecurringConfirmation else { return }

        let calendar = Calendar.current
        let now = Date()

        do {
            if accountingReminder == "daily" {
                let startOfDay = calendar.startOfDay(for: now)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

                let descriptor = FetchDescriptor<TransactionRecord>(
                    predicate: #Predicate<TransactionRecord> { transaction in
                        transaction.date >= startOfDay && transaction.date < endOfDay
                    }
                )

                let count = try modelContext.fetchCount(descriptor)

                if count == 0 {
                    reminderMessage = "今天还没有记账哦，要记一笔吗？"
                    showingReminder = true
                }

            } else if accountingReminder == "monthly" {
                let components = calendar.dateComponents([.year, .month], from: now)
                let startOfMonth = calendar.date(from: components)!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

                let descriptor = FetchDescriptor<TransactionRecord>(
                    predicate: #Predicate<TransactionRecord> { transaction in
                        transaction.date >= startOfMonth && transaction.date < endOfMonth
                    }
                )

                let count = try modelContext.fetchCount(descriptor)

                if count == 0 {
                    let monthFormatter = DateFormatter()
                    monthFormatter.dateFormat = "M月"
                    let monthStr = monthFormatter.string(from: now)
                    reminderMessage = "\(monthStr)还没有记账记录，要开始记账吗？"
                    showingReminder = true
                }
            }
        } catch {
            print("检查记账记录失败: \(error)")
        }
    }
}

// MARK: - 定期交易确认视图

struct RecurringTransactionConfirmationView: View {
    let pendingTransactions: [RecurringTransaction]
    let onConfirm: ([RecurringTransaction]) -> Void
    let onDismiss: () -> Void

    @State private var selectedTransactions: Set<UUID> = []
    @Query private var categories: [Category]

    init(pendingTransactions: [RecurringTransaction], onConfirm: @escaping ([RecurringTransaction]) -> Void, onDismiss: @escaping () -> Void) {
        self.pendingTransactions = pendingTransactions
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        // 默认全选
        _selectedTransactions = State(initialValue: Set(pendingTransactions.map { $0.id }))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题区域
                VStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)

                    Text("今日定期交易")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("以下是今天需要记录的定期交易")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)

                // 交易列表
                List {
                    ForEach(pendingTransactions) { transaction in
                        RecurringConfirmationRow(
                            transaction: transaction,
                            isSelected: selectedTransactions.contains(transaction.id),
                            categoryName: getCategoryName(for: transaction.categoryId)
                        ) {
                            if selectedTransactions.contains(transaction.id) {
                                selectedTransactions.remove(transaction.id)
                            } else {
                                selectedTransactions.insert(transaction.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                // 底部按钮
                VStack(spacing: 12) {
                    Button {
                        let selected = pendingTransactions.filter { selectedTransactions.contains($0.id) }
                        onConfirm(selected)
                    } label: {
                        Text("确认记录 (\(selectedTransactions.count))")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTransactions.isEmpty)

                    Button {
                        onDismiss()
                    } label: {
                        Text("稍后再说")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedTransactions.count == pendingTransactions.count {
                            selectedTransactions.removeAll()
                        } else {
                            selectedTransactions = Set(pendingTransactions.map { $0.id })
                        }
                    } label: {
                        Text(selectedTransactions.count == pendingTransactions.count ? "取消全选" : "全选")
                            .font(.subheadline)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func getCategoryName(for categoryId: UUID?) -> String {
        guard let id = categoryId else { return "" }
        return categories.first { $0.id == id }?.name ?? ""
    }
}

struct RecurringConfirmationRow: View {
    let transaction: RecurringTransaction
    let isSelected: Bool
    let categoryName: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.name)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(transaction.frequency.displayName)
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

                Text("¥\(NSDecimalNumber(decimal: transaction.amount).doubleValue, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(transaction.type == .expense ? .red : .green)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
