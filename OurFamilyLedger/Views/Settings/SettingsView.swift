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
                        Text("自定义 API").tag("custom")
                    }
                    .onChange(of: aiProvider) { _, newValue in
                        if newValue == "openai" {
                            aiModel = "gpt-4o-mini"
                        }
                    }

                    // 模型选择
                    if fetchedModels.isEmpty {
                        Picker("模型", selection: $aiModel) {
                            if aiProvider == "openai" {
                                Text("GPT-4o Mini").tag("gpt-4o-mini")
                                Text("GPT-4o").tag("gpt-4o")
                                Text("GPT-4 Turbo").tag("gpt-4-turbo")
                                Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                            } else {
                                Text("自定义模型").tag(aiModel)
                            }
                        }
                    } else {
                        Picker("模型", selection: $aiModel) {
                            ForEach(fetchedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }

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
                Section {
                    Picker("默认货币", selection: $defaultCurrency) {
                        ForEach(SupportedCurrency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency.rawValue)
                        }
                    }

                    NavigationLink {
                        RemindersListView()
                    } label: {
                        Text("记账提醒")
                    }

                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Text("分类管理")
                    }

                    NavigationLink {
                        RecurringTransactionListView()
                    } label: {
                        HStack {
                            Text("定期交易")
                            Spacer()
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("账本设置")
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
                        Text(Bundle.main.fullVersionString)
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
                fetchedModels = []
                modelFetchError = nil
            }
        }
    }

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
                    Text("支持 OpenAI 兼容的 API 端点（如 local AI、第三方代理等）")
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
        openaiKey = (try? KeychainService.shared.getAPIKey(for: .openai)) ?? ""
        customKey = (try? KeychainService.shared.getAPIKey(for: .custom)) ?? ""
        customEndpoint = (try? KeychainService.shared.getCustomEndpoint()) ?? ""
    }

    private func saveKeys() {
        do {
            if !openaiKey.isEmpty {
                try KeychainService.shared.saveAPIKey(openaiKey, for: .openai)
            } else {
                try? KeychainService.shared.deleteAPIKey(for: .openai)
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
