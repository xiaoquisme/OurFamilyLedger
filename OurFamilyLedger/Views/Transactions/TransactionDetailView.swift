import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [Category]
    @Query private var members: [Member]

    @Bindable var transaction: TransactionRecord

    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false

    // 编辑状态的临时变量
    @State private var editAmount: String = ""
    @State private var editNote: String = ""
    @State private var editMerchant: String = ""
    @State private var editDate: Date = Date()
    @State private var editType: TransactionType = .expense
    @State private var editCategoryId: UUID?
    @State private var editPayerId: UUID?

    var body: some View {
        List {
            if isEditing {
                editingContent
            } else {
                viewingContent
            }
        }
        .navigationTitle(isEditing ? "编辑交易" : "交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("保存") {
                        saveChanges()
                    }
                } else {
                    Button("编辑") {
                        startEditing()
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        cancelEditing()
                    }
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive) {
                deleteTransaction()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除这笔交易吗？此操作不可撤销。")
        }
    }

    // MARK: - 查看模式

    private var viewingContent: some View {
        Group {
            // 金额区域
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text(transaction.type == .expense ? "支出" : "收入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("¥\(formattedAmount)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(transaction.type == .expense ? .red : .green)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }

            // 基本信息
            Section("基本信息") {
                DetailRow(title: "备注", value: transaction.note.isEmpty ? "无" : transaction.note)
                DetailRow(title: "商户", value: transaction.merchant.isEmpty ? "无" : transaction.merchant)
                DetailRow(title: "日期", value: formattedDate)
                DetailRow(title: "分类", value: categoryName)
            }

            // 付款信息
            Section("付款信息") {
                DetailRow(title: "付款人", value: payerName)

                if transaction.participantIds.count > 1 {
                    DetailRow(title: "参与人数", value: "\(transaction.participantIds.count)人")
                    DetailRow(title: "人均金额", value: "¥\(splitAmountText)")
                }
            }

            // 其他信息
            Section("其他") {
                DetailRow(title: "来源", value: sourceText)
                DetailRow(title: "创建时间", value: formattedCreatedAt)
            }

            // 删除按钮
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("删除交易")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - 编辑模式

    private var editingContent: some View {
        Group {
            Section("金额") {
                HStack {
                    Text("¥")
                    TextField("金额", text: $editAmount)
                        .keyboardType(.decimalPad)
                }

                Picker("类型", selection: $editType) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }
            }

            Section("基本信息") {
                TextField("备注", text: $editNote)
                TextField("商户", text: $editMerchant)
                DatePicker("日期", selection: $editDate, displayedComponents: .date)
            }

            Section("分类") {
                Picker("分类", selection: $editCategoryId) {
                    Text("不选择").tag(nil as UUID?)
                    ForEach(filteredCategories) { category in
                        Text(category.name).tag(category.id as UUID?)
                    }
                }
            }

            Section("付款人") {
                Picker("付款人", selection: $editPayerId) {
                    Text("不选择").tag(nil as UUID?)
                    ForEach(members) { member in
                        Text(member.name).tag(member.id as UUID?)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredCategories: [Category] {
        categories.filter { $0.type == editType }
    }

    private var formattedAmount: String {
        String(format: "%.2f", NSDecimalNumber(decimal: transaction.amount).doubleValue)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: transaction.date)
    }

    private var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: transaction.createdAt)
    }

    private var categoryName: String {
        guard let categoryId = transaction.categoryId else { return "未分类" }
        return categories.first { $0.id == categoryId }?.name ?? "未分类"
    }

    private var payerName: String {
        guard let payerId = transaction.payerId else { return "未指定" }
        return members.first { $0.id == payerId }?.name ?? "未指定"
    }

    private var splitAmountText: String {
        let count = max(1, transaction.participantIds.count)
        let split = transaction.amount / Decimal(count)
        return String(format: "%.2f", NSDecimalNumber(decimal: split).doubleValue)
    }

    private var sourceText: String {
        switch transaction.source {
        case .manual: return "手动输入"
        case .text: return "文本输入"
        case .appleOCR: return "Apple OCR"
        case .visionModel: return "视觉模型"
        }
    }

    // MARK: - Actions

    private func startEditing() {
        editAmount = formattedAmount
        editNote = transaction.note
        editMerchant = transaction.merchant
        editDate = transaction.date
        editType = transaction.type
        editCategoryId = transaction.categoryId
        editPayerId = transaction.payerId
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
    }

    private func saveChanges() {
        guard let amount = Decimal(string: editAmount) else { return }

        transaction.amount = amount
        transaction.note = editNote
        transaction.merchant = editMerchant
        transaction.date = editDate
        transaction.type = editType
        transaction.categoryId = editCategoryId
        transaction.payerId = editPayerId
        transaction.updatedAt = Date()

        try? modelContext.save()
        isEditing = false
    }

    private func deleteTransaction() {
        modelContext.delete(transaction)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    NavigationStack {
        Text("Preview")
    }
}
