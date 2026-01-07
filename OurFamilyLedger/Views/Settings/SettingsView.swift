import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("aiModel") private var aiModel = "gpt-4o-mini"
    @AppStorage("ocrMode") private var ocrMode = "local"
    @AppStorage("defaultCurrency") private var defaultCurrency = "CNY"

    @State private var showingAPIKeySettings = false
    @State private var showingTestParse = false
    @State private var showingExportSheet = false
    @State private var fetchedModels: [AIModel] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    var body: some View {
        NavigationStack {
            List {
                // AI 设置
                Section {
                    Picker("AI 提供商", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Claude").tag("claude")
                        Text("自定义").tag("custom")
                    }
                    .onChange(of: aiProvider) { _, newValue in
                        // 切换提供商时设置默认模型
                        switch newValue {
                        case "openai":
                            aiModel = "gpt-4o-mini"
                        case "claude":
                            aiModel = "claude-3-5-sonnet-20241022"
                        default:
                            break
                        }
                    }

                    // 模型选择
                    if fetchedModels.isEmpty {
                        // 使用默认模型列表
                        Picker("模型", selection: $aiModel) {
                            if aiProvider == "openai" {
                                Text("GPT-4o Mini").tag("gpt-4o-mini")
                                Text("GPT-4o").tag("gpt-4o")
                                Text("GPT-4 Turbo").tag("gpt-4-turbo")
                                Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                            } else if aiProvider == "claude" {
                                Text("Claude 3.5 Sonnet").tag("claude-3-5-sonnet-20241022")
                                Text("Claude 3.5 Haiku").tag("claude-3-5-haiku-20241022")
                                Text("Claude 3 Opus").tag("claude-3-opus-20240229")
                            } else {
                                Text("自定义模型").tag(aiModel)
                            }
                        }
                    } else {
                        // 使用从 API 获取的模型列表
                        Picker("模型", selection: $aiModel) {
                            ForEach(fetchedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }

                    // 刷新模型列表按钮
                    Button {
                        fetchModels()
                    } label: {
                        HStack {
                            Text("刷新模型列表")
                            Spacer()
                            if isFetchingModels {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isFetchingModels)

                    if let error = modelFetchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if aiProvider == "custom" {
                        HStack {
                            Text("模型名称")
                            Spacer()
                            TextField("model-name", text: $aiModel)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showingAPIKeySettings = true
                    } label: {
                        HStack {
                            Text("API Key 设置")
                            Spacer()
                            Image(systemName: "key")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showingTestParse = true
                    } label: {
                        HStack {
                            Text("测试解析")
                            Spacer()
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("AI 模型")
                } footer: {
                    Text("配置用于解析记账信息的 AI 模型")
                }

                // OCR 设置
                Section {
                    Picker("OCR 模式", selection: $ocrMode) {
                        Text("仅本地 OCR").tag("local")
                        Text("允许第三方识图").tag("remote")
                    }
                } header: {
                    Text("OCR 设置")
                } footer: {
                    if ocrMode == "remote" {
                        Text("使用第三方识图时，图片将发送到 AI 服务进行识别")
                            .foregroundStyle(.orange)
                    } else {
                        Text("本地 OCR 使用 Apple Vision，隐私友好")
                    }
                }

                // 账本设置
                Section("账本设置") {
                    Picker("默认货币", selection: $defaultCurrency) {
                        ForEach(SupportedCurrency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency.rawValue)
                        }
                    }

                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Text("分类管理")
                    }
                }

                // 数据
                Section("数据") {
                    Button {
                        showingExportSheet = true
                    } label: {
                        HStack {
                            Text("导出数据")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ImportDataView()
                    } label: {
                        Text("导入数据")
                    }

                    NavigationLink {
                        iCloudStatusView()
                    } label: {
                        HStack {
                            Text("iCloud 状态")
                            Spacer()
                            Image(systemName: "icloud")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/xiaoquisme/OurFamilyLedger")!) {
                        HStack {
                            Text("开源许可")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingAPIKeySettings) {
                APIKeySettingsView()
            }
            .sheet(isPresented: $showingTestParse) {
                TestParseView()
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportDataView()
            }
            .onChange(of: aiProvider) { _, _ in
                // 切换提供商时清空已获取的模型列表
                fetchedModels = []
                modelFetchError = nil
            }
        }
    }

    // MARK: - Fetch Models

    private func fetchModels() {
        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let providerEnum = AIProvider(rawValue: aiProvider) ?? .openai

                guard let apiKey = try? KeychainService.shared.getAPIKey(for: providerEnum),
                      !apiKey.isEmpty else {
                    await MainActor.run {
                        modelFetchError = "请先配置 API Key"
                        isFetchingModels = false
                    }
                    return
                }

                let endpoint = try? KeychainService.shared.getCustomEndpoint()
                let aiService = AIServiceFactory.create(provider: providerEnum, apiKey: apiKey, endpoint: endpoint)

                let models = try await aiService.fetchModels()

                await MainActor.run {
                    fetchedModels = models
                    isFetchingModels = false

                    // 如果当前选择的模型不在列表中，选择第一个
                    if !models.isEmpty && !models.contains(where: { $0.id == aiModel }) {
                        aiModel = models.first?.id ?? aiModel
                    }
                }
            } catch {
                await MainActor.run {
                    modelFetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }
}

// MARK: - API Key Settings

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiProvider") private var aiProvider = "openai"

    @State private var openaiKey = ""
    @State private var claudeKey = ""
    @State private var customEndpoint = ""
    @State private var customKey = ""
    @State private var showingKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureInputField(
                        text: $openaiKey,
                        placeholder: "sk-...",
                        showingText: showingKey
                    )
                }

                Section("Claude") {
                    SecureInputField(
                        text: $claudeKey,
                        placeholder: "sk-ant-...",
                        showingText: showingKey
                    )
                }

                Section {
                    TextField("API 端点", text: $customEndpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureInputField(
                        text: $customKey,
                        placeholder: "API Key",
                        showingText: showingKey
                    )
                } header: {
                    Text("自定义 API")
                } footer: {
                    Text("支持 OpenAI 兼容的 API 端点")
                }

                Section {
                    Toggle("显示密钥", isOn: $showingKey)
                }
            }
            .navigationTitle("API Key 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveKeys()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadKeys()
            }
        }
    }

    private func loadKeys() {
        // 从 Keychain 加载
        openaiKey = (try? KeychainService.shared.getAPIKey(for: .openai)) ?? ""
        claudeKey = (try? KeychainService.shared.getAPIKey(for: .claude)) ?? ""
        customKey = (try? KeychainService.shared.getAPIKey(for: .custom)) ?? ""
        customEndpoint = (try? KeychainService.shared.getCustomEndpoint()) ?? ""
    }

    private func saveKeys() {
        // 保存到 Keychain
        do {
            if !openaiKey.isEmpty {
                try KeychainService.shared.saveAPIKey(openaiKey, for: .openai)
            } else {
                try? KeychainService.shared.deleteAPIKey(for: .openai)
            }

            if !claudeKey.isEmpty {
                try KeychainService.shared.saveAPIKey(claudeKey, for: .claude)
            } else {
                try? KeychainService.shared.deleteAPIKey(for: .claude)
            }

            if !customKey.isEmpty {
                try KeychainService.shared.saveAPIKey(customKey, for: .custom)
            } else {
                try? KeychainService.shared.deleteAPIKey(for: .custom)
            }

            if !customEndpoint.isEmpty {
                try KeychainService.shared.saveCustomEndpoint(customEndpoint)
            }
        } catch {
            print("保存 API Key 失败: \(error)")
        }
    }
}

struct SecureInputField: View {
    @Binding var text: String
    let placeholder: String
    let showingText: Bool

    var body: some View {
        if showingText {
            TextField(placeholder, text: $text)
                .font(.system(.body, design: .monospaced))
                .autocapitalization(.none)
                .autocorrectionDisabled()
        } else {
            SecureField(placeholder, text: $text)
                .font(.system(.body, design: .monospaced))
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Test Parse View

struct TestParseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var result: TransactionDraft?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 输入区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入测试文本")
                        .font(.headline)

                    TextEditor(text: $inputText)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        testParse()
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            }
                            Text("测试解析")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.isEmpty || isProcessing)
                }

                Divider()

                // 结果区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("解析结果")
                        .font(.headline)

                    if let result = result {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("金额: ¥\(NSDecimalNumber(decimal: result.amount).doubleValue)")
                            Text("分类: \(result.categoryName)")
                            Text("付款人: \(result.payerName)")
                            Text("参与人: \(result.participantNames.joined(separator: "、"))")
                            Text("备注: \(result.note)")
                        }
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    } else {
                        Text("输入文本后点击测试解析")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("测试解析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func testParse() {
        isProcessing = true
        errorMessage = nil
        result = nil

        Task {
            do {
                // 获取当前 AI 配置
                let providerString = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
                let provider = AIProvider(rawValue: providerString) ?? .openai

                guard let apiKey = try? KeychainService.shared.getAPIKey(for: provider),
                      !apiKey.isEmpty else {
                    await MainActor.run {
                        errorMessage = "请先在设置中配置 API Key"
                        isProcessing = false
                    }
                    return
                }

                let endpoint = try? KeychainService.shared.getCustomEndpoint()
                let model = UserDefaults.standard.string(forKey: "aiModel")
                let aiService = AIServiceFactory.create(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)

                let drafts = try await aiService.parseTransaction(from: inputText)

                await MainActor.run {
                    if let firstDraft = drafts.first {
                        result = firstDraft
                    } else {
                        errorMessage = "未能识别交易信息"
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Category Settings View

struct CategorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingAddCategory = false

    init() {}

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var incomeCategories: [Category] {
        categories.filter { $0.type == .income }
    }

    var body: some View {
        List {
            Section("支出分类") {
                ForEach(expenseCategories) { category in
                    CategoryRow(category: category)
                }
                .onDelete { indexSet in
                    deleteCategories(from: expenseCategories, at: indexSet)
                }
            }

            Section("收入分类") {
                ForEach(incomeCategories) { category in
                    CategoryRow(category: category)
                }
                .onDelete { indexSet in
                    deleteCategories(from: incomeCategories, at: indexSet)
                }
            }

            Section {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("添加分类", systemImage: "plus")
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView()
        }
    }

    private func deleteCategories(from list: [Category], at offsets: IndexSet) {
        for index in offsets {
            let category = list[index]
            modelContext.delete(category)
        }
    }
}

struct CategoryRow: View {
    let category: Category

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundStyle(Color.blue)
                .frame(width: 24)

            Text(category.name)

            Spacer()

            if category.isDefault {
                Text("默认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var icon = "tag"
    @State private var type: TransactionType = .expense

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)

                Picker("类型", selection: $type) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }

                // TODO: 图标选择器
            }
            .navigationTitle("添加分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addCategory()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addCategory() {
        let category = Category(
            name: name,
            icon: icon,
            type: type
        )
        modelContext.insert(category)
        dismiss()
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMonth = Date()
    @State private var exportAll = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingShareSheet = false
    @State private var exportFileURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("导出所有数据", isOn: $exportAll)

                    if !exportAll {
                        DatePicker(
                            "选择月份",
                            selection: $selectedMonth,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Label("导出 CSV", systemImage: "doc.text")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                } footer: {
                    Text("导出后可通过「文件」App、AirDrop、邮件等方式分享")
                }

                if let error = exportError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("导出数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exportData() {
        isExporting = true
        exportError = nil

        Task {
            do {
                // 获取交易记录
                var descriptor = FetchDescriptor<TransactionRecord>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )

                if !exportAll {
                    // 筛选指定月份
                    let calendar = Calendar.current
                    let year = calendar.component(.year, from: selectedMonth)
                    let month = calendar.component(.month, from: selectedMonth)

                    let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
                    let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!

                    descriptor.predicate = #Predicate<TransactionRecord> { transaction in
                        transaction.date >= startOfMonth && transaction.date <= endOfMonth
                    }
                }

                let transactions = try modelContext.fetch(descriptor)

                if transactions.isEmpty {
                    await MainActor.run {
                        exportError = "没有可导出的数据"
                        isExporting = false
                    }
                    return
                }

                // 生成 CSV 内容
                let csvContent = generateCSV(from: transactions)

                // 创建临时文件
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
                let fileName = "OurFamilyLedger_\(dateFormatter.string(from: Date())).csv"

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    exportFileURL = tempURL
                    showingShareSheet = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = "导出失败: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }

    private func generateCSV(from transactions: [TransactionRecord]) -> String {
        var csv = "id,date,amount,type,category_id,payer_id,participants,note,merchant,source,created_at,updated_at\n"

        let dateFormatter = ISO8601DateFormatter()

        for transaction in transactions {
            let participantsStr = transaction.participantIds.map { $0.uuidString }.joined(separator: ";")
            let typeStr = transaction.type == .expense ? "expense" : "income"

            let row = [
                transaction.id.uuidString,
                dateFormatter.string(from: transaction.date),
                "\(transaction.amount)",
                typeStr,
                transaction.categoryId?.uuidString ?? "",
                transaction.payerId?.uuidString ?? "",
                participantsStr,
                escapeCSV(transaction.note),
                escapeCSV(transaction.merchant),
                transaction.source.rawValue,
                dateFormatter.string(from: transaction.createdAt),
                dateFormatter.string(from: transaction.updatedAt)
            ].joined(separator: ",")

            csv += row + "\n"
        }

        return csv
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Import Data View

struct ImportDataView: View {
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("导入 CSV 数据")
                .font(.title2)
                .fontWeight(.bold)

            Text("选择符合格式要求的 CSV 文件进行导入")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                showingFilePicker = true
            } label: {
                Label("选择文件", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("导入数据")
    }
}

// MARK: - iCloud Status View

struct iCloudStatusView: View {
    @State private var iCloudAvailable = false
    @State private var iCloudPath: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("iCloud 状态")
                    Spacer()
                    if iCloudAvailable {
                        Label("可用", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("不可用", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let path = iCloudPath {
                    HStack {
                        Text("账本位置")
                        Spacer()
                        Text(path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                Button("刷新状态") {
                    checkiCloudStatus()
                }
            }
        }
        .navigationTitle("iCloud 状态")
        .onAppear {
            checkiCloudStatus()
        }
    }

    private func checkiCloudStatus() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    }
}

#Preview {
    SettingsView()
}
