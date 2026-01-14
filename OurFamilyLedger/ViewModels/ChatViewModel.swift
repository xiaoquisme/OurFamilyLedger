import Foundation
import SwiftUI
import SwiftData

/// 聊天记账 ViewModel
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var pendingDrafts: [TransactionDraft] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var canRetry = false

    private var modelContext: ModelContext?
    private var aiService: AIServiceProtocol?
    private let ocrService = AppleOCRService()

    // 重试相关
    private var lastInputText: String = ""
    private var lastInputImages: [UIImage] = []
    private var retryCount = 0
    private let maxRetryCount = 3

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupAIService()
    }

    private func setupAIService() {
        // 从 UserDefaults 和 Keychain 加载配置
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        let model = UserDefaults.standard.string(forKey: "aiModel")

        if let apiKey = try? KeychainService.shared.getAPIKey(for: provider), !apiKey.isEmpty {
            let endpoint = try? KeychainService.shared.getCustomEndpoint()
            aiService = AIServiceFactory.create(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)
        }
    }

    // MARK: - Message Processing

    /// 处理用户输入
    func processInput(text: String, images: [UIImage]) async {
        guard !text.isEmpty || !images.isEmpty else { return }

        // 保存输入用于重试
        lastInputText = text
        lastInputImages = images
        retryCount = 0
        canRetry = false

        // 添加用户消息
        let userMessage = ChatMessage(
            type: .user,
            text: text,
            images: images
        )
        messages.append(userMessage)

        await executeProcessing(text: text, images: images)
    }

    /// 重试上次失败的请求
    func retry() async {
        guard canRetry, retryCount < maxRetryCount else { return }

        retryCount += 1
        canRetry = false

        // 添加重试消息
        let retryMessage = ChatMessage(
            type: .system,
            text: "正在重试 (\(retryCount)/\(maxRetryCount))..."
        )
        messages.append(retryMessage)

        await executeProcessing(text: lastInputText, images: lastInputImages)
    }

    /// 执行处理逻辑
    private func executeProcessing(text: String, images: [UIImage]) async {
        isProcessing = true
        errorMessage = nil

        do {
            var drafts: [TransactionDraft] = []

            if !images.isEmpty {
                // 处理图片
                drafts = try await processImages(images, additionalText: text)
            } else if !text.isEmpty {
                // 处理纯文本
                drafts = try await processText(text)
            }

            if drafts.isEmpty {
                // 没有识别到交易
                let assistantMessage = ChatMessage(
                    type: .assistant,
                    text: "抱歉，我没有从内容中识别到交易信息。请尝试提供更清晰的描述或截图。"
                )
                messages.append(assistantMessage)
            } else {
                // 添加待确认的草稿
                pendingDrafts.append(contentsOf: drafts)

                let countText = drafts.count > 1 ? "\(drafts.count)笔交易" : "一笔交易"
                let assistantMessage = ChatMessage(
                    type: .assistant,
                    text: "已识别到\(countText)，请确认信息是否正确。"
                )
                messages.append(assistantMessage)
            }

            // 成功后重置重试状态
            retryCount = 0
            canRetry = false
        } catch {
            errorMessage = error.localizedDescription

            // 判断是否可以重试
            let canRetryError = retryCount < maxRetryCount
            canRetry = canRetryError

            let retryHint = canRetryError ? " 点击重试按钮再试一次。" : ""
            let assistantMessage = ChatMessage(
                type: .assistant,
                text: "处理失败：\(error.localizedDescription)\(retryHint)"
            )
            messages.append(assistantMessage)
        }

        isProcessing = false
    }

    /// 处理图片
    private func processImages(_ images: [UIImage], additionalText: String) async throws -> [TransactionDraft] {
        var allDrafts: [TransactionDraft] = []

        for image in images {
            // 先进行 OCR
            let ocrResult = try await ocrService.recognizeText(from: image)

            // 检查是否使用远程 AI
            let ocrMode = UserDefaults.standard.string(forKey: "ocrMode") ?? "local"

            if let aiService = aiService {
                if ocrMode == "remote" {
                    // 发送图片到 AI
                    let drafts = try await aiService.parseTransaction(from: image, ocrText: ocrResult.text)
                    allDrafts.append(contentsOf: drafts)
                } else {
                    // 只使用 OCR 文本
                    var combinedText = ocrResult.text
                    if !additionalText.isEmpty {
                        combinedText += "\n用户补充：\(additionalText)"
                    }
                    let drafts = try await aiService.parseTransaction(from: combinedText)
                    allDrafts.append(contentsOf: drafts)
                }
            } else {
                // 没有配置 AI，使用简单解析
                let draft = parseSimple(from: ocrResult.text)
                if let draft = draft {
                    allDrafts.append(draft)
                }
            }
        }

        return allDrafts
    }

    /// 处理纯文本
    private func processText(_ text: String) async throws -> [TransactionDraft] {
        if let aiService = aiService {
            return try await aiService.parseTransaction(from: text)
        } else {
            // 没有配置 AI，使用简单解析
            if let draft = parseSimple(from: text) {
                return [draft]
            }
            return []
        }
    }

    /// 简单解析（不使用 AI）
    private func parseSimple(from text: String) -> TransactionDraft? {
        // 尝试提取金额
        let amountPattern = #"[¥￥$]?\s*(\d+\.?\d*)"#
        guard let amountMatch = text.range(of: amountPattern, options: .regularExpression) else {
            return nil
        }

        let amountString = text[amountMatch]
            .replacingOccurrences(of: "[¥￥$\\s]", with: "", options: .regularExpression)

        guard let amount = Decimal(string: amountString) else {
            return nil
        }

        return TransactionDraft(
            amount: amount,
            categoryName: "其他",
            payerName: "",
            participantNames: [],
            note: text,
            source: .text
        )
    }

    // MARK: - Draft Management

    /// 确认草稿入账
    func confirmDraft(_ draft: TransactionDraft) async {
        guard let modelContext = modelContext else { return }

        // 查找或创建分类
        let categoryId = await findOrCreateCategory(name: draft.categoryName)

        // 查找或创建付款人
        let payerId = await findOrCreateMember(name: draft.payerName)

        // 查找或创建参与人
        var participantIds: [UUID] = []
        if draft.participantNames.isEmpty {
            // 没有指定参与人时，使用默认成员
            if let defaultId = getDefaultMemberId() {
                participantIds.append(defaultId)
            }
        } else {
            for name in draft.participantNames {
                let id = await findOrCreateMember(name: name)
                if let id = id {
                    participantIds.append(id)
                }
            }
        }

        // 创建交易记录
        let transaction = TransactionRecord(
            date: draft.date,
            amount: draft.amount,
            type: draft.type,
            categoryId: categoryId,
            payerId: payerId,
            participantIds: participantIds,
            note: draft.note,
            merchant: draft.merchant,
            source: draft.source,
            ocrText: draft.ocrText,
            confidenceAmount: draft.confidenceAmount,
            confidenceDate: draft.confidenceDate
        )

        modelContext.insert(transaction)

        // 从待确认列表移除
        pendingDrafts.removeAll { $0.id == draft.id }

        // 添加确认消息
        let message = ChatMessage(
            type: .system,
            text: "已入账: \(draft.categoryName) ¥\(draft.amount)"
        )
        messages.append(message)

        // 写入 iCloud CSV 文件
        await SyncService.shared.writeTransaction(
            transaction,
            categoryName: draft.categoryName,
            payerName: draft.payerName,
            participantNames: draft.participantNames,
            context: modelContext
        )
    }

    /// 确认所有草稿
    func confirmAllDrafts() async {
        for draft in pendingDrafts {
            await confirmDraft(draft)
        }
    }

    /// 编辑草稿
    func updateDraft(_ draft: TransactionDraft, with updated: TransactionDraft) {
        if let index = pendingDrafts.firstIndex(where: { $0.id == draft.id }) {
            pendingDrafts[index] = updated
        }
    }

    /// 删除草稿
    func deleteDraft(_ draft: TransactionDraft) {
        pendingDrafts.removeAll { $0.id == draft.id }
    }

    // MARK: - Helpers

    private func findOrCreateCategory(name: String) async -> UUID? {
        guard let modelContext = modelContext else { return nil }

        // 查找现有分类
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == name }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing.id
        }

        // 创建新分类
        let category = Category(name: name, type: .expense)
        modelContext.insert(category)
        return category.id
    }

    private func findOrCreateMember(name: String) async -> UUID? {
        guard let modelContext = modelContext else { return nil }

        // 如果名字为空，返回默认成员
        if name.isEmpty {
            return getDefaultMemberId()
        }

        // 查找现有成员
        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.name == name || $0.nickname == name }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing.id
        }

        // 创建新成员
        let member = Member(name: name)
        modelContext.insert(member)
        return member.id
    }

    /// 获取默认成员 ID
    private func getDefaultMemberId() -> UUID? {
        let defaultMemberIdString = UserDefaults.standard.string(forKey: "defaultMemberId") ?? ""
        guard !defaultMemberIdString.isEmpty else { return nil }
        return UUID(uuidString: defaultMemberIdString)
    }

    // MARK: - Clarification

    /// 处理用户澄清
    func handleClarification(_ text: String, for draft: TransactionDraft) async {
        // 分析用户输入，更新草稿
        let lowerText = text.lowercased()

        var updated = draft

        // 检查是否是金额修正
        let amountPattern = #"(\d+\.?\d*)"#
        if let match = text.range(of: amountPattern, options: .regularExpression) {
            let amountString = String(text[match])
            if let newAmount = Decimal(string: amountString) {
                updated = TransactionDraft(
                    id: draft.id,
                    date: draft.date,
                    amount: newAmount,
                    type: draft.type,
                    categoryName: draft.categoryName,
                    payerName: draft.payerName,
                    participantNames: draft.participantNames,
                    note: draft.note,
                    merchant: draft.merchant,
                    source: draft.source,
                    ocrText: draft.ocrText,
                    confidenceAmount: 1.0,
                    confidenceDate: draft.confidenceDate
                )
            }
        }

        // 检查是否是类型修正
        if lowerText.contains("收入") || lowerText.contains("income") {
            updated = TransactionDraft(
                id: updated.id,
                date: updated.date,
                amount: updated.amount,
                type: .income,
                categoryName: updated.categoryName,
                payerName: updated.payerName,
                participantNames: updated.participantNames,
                note: updated.note,
                merchant: updated.merchant,
                source: updated.source,
                ocrText: updated.ocrText,
                confidenceAmount: updated.confidenceAmount,
                confidenceDate: updated.confidenceDate
            )
        }

        updateDraft(draft, with: updated)
    }
}
