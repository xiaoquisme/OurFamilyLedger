import SwiftUI

struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("ocrMode") private var ocrMode = "local"
    @AppStorage("defaultCurrency") private var defaultCurrency = "CNY"

    @State private var showingAPIKeySettings = false
    @State private var showingTestParse = false
    @State private var showingExportSheet = false

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

                    Link(destination: URL(string: "https://github.com")!) {
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

                Section("自定义 API") {
                    TextField("API 端点", text: $customEndpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureInputField(
                        text: $customKey,
                        placeholder: "API Key",
                        showingText: showingKey
                    )
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
        // TODO: 从 Keychain 加载
    }

    private func saveKeys() {
        // TODO: 保存到 Keychain
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
                            Text("金额: ¥\(result.amount)")
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

        // TODO: 调用 AI 服务进行解析
        Task {
            try? await Task.sleep(for: .seconds(1))

            await MainActor.run {
                // 模拟解析结果
                result = TransactionDraft(
                    amount: 128.00,
                    categoryName: "餐饮",
                    payerName: "我",
                    participantNames: ["我", "家人"],
                    note: inputText,
                    source: .text
                )
                isProcessing = false
            }
        }
    }
}

// MARK: - Category Settings View

struct CategorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingAddCategory = false

    var body: some View {
        List {
            Section("支出分类") {
                ForEach(categories.filter { $0.type == .expense }) { category in
                    CategoryRow(category: category)
                }
            }

            Section("收入分类") {
                ForEach(categories.filter { $0.type == .income }) { category in
                    CategoryRow(category: category)
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
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView()
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

    @State private var selectedMonth = Date()
    @State private var exportAll = true

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
                        Label("导出 CSV", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("导出数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exportData() {
        // TODO: 实现导出逻辑
        dismiss()
    }
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
