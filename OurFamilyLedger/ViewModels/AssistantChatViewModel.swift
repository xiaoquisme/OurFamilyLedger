import Foundation
import SwiftUI
import SwiftData

/// 助手聊天消息
struct AssistantChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    static func == (lhs: AssistantChatMessage, rhs: AssistantChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// 智能助手聊天 ViewModel
/// 支持 Function Calling，可以通过对话执行应用功能
@MainActor
final class AssistantChatViewModel: ObservableObject {
    @Published var messages: [AssistantChatMessage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private var modelContext: ModelContext?
    private var functionCallingService: FunctionCallingAIService?
    private let keychainService: KeychainServiceProtocol

    // MARK: - Initialization

    init(keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.keychainService = keychainService

        // 添加欢迎消息
        messages.append(AssistantChatMessage(
            role: .assistant,
            content: "你好！我是你的家庭记账助手。我可以帮你：\n\n" +
            "📝 **记账** - 告诉我你花了什么钱\n" +
            "📊 **查询** - 查看交易记录和统计\n" +
            "👨‍👩‍👧 **管理** - 管理分类、成员、提醒\n\n" +
            "试试说「今天午餐花了35元」或「这个月花了多少钱」"
        ))
    }

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupService()
    }

    private func setupService() {
        guard let modelContext = modelContext else { return }

        // 从 UserDefaults 和 Keychain 加载配置
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        let model = UserDefaults.standard.string(forKey: "aiModel")

        if let apiKey = try? keychainService.getAPIKey(for: provider), !apiKey.isEmpty {
            let endpoint = try? keychainService.getCustomEndpoint()

            let config = AIServiceConfig(
                provider: provider,
                apiKey: apiKey,
                endpoint: endpoint,
                model: model
            )

            functionCallingService = FunctionCallingAIService(config: config, modelContext: modelContext)
        }
    }

    // MARK: - Message Handling

    /// 发送消息
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 添加用户消息
        let userMessage = AssistantChatMessage(role: .user, content: text)
        messages.append(userMessage)

        // 检查是否配置了 AI
        guard let service = functionCallingService else {
            messages.append(AssistantChatMessage(
                role: .assistant,
                content: "请先在设置中配置 AI 服务的 API Key。"
            ))
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            let response = try await service.sendMessage(text)

            let assistantMessage = AssistantChatMessage(
                role: .assistant,
                content: response
            )
            messages.append(assistantMessage)
        } catch {
            errorMessage = error.localizedDescription
            messages.append(AssistantChatMessage(
                role: .assistant,
                content: "抱歉，处理请求时遇到问题：\(error.localizedDescription)"
            ))
        }

        isProcessing = false
    }

    /// 清空对话
    func clearMessages() {
        messages.removeAll()
        messages.append(AssistantChatMessage(
            role: .assistant,
            content: "对话已清空。有什么可以帮你的吗？"
        ))
    }

    // MARK: - Quick Actions

    /// 快捷操作
    enum QuickAction: String, CaseIterable {
        case monthlySummary = "这个月的收支情况"
        case todayTransactions = "今天的交易"
        case listCategories = "查看所有分类"
        case listMembers = "查看家庭成员"

        var icon: String {
            switch self {
            case .monthlySummary: return "chart.pie"
            case .todayTransactions: return "list.bullet"
            case .listCategories: return "tag"
            case .listMembers: return "person.3"
            }
        }
    }

    /// 执行快捷操作
    func executeQuickAction(_ action: QuickAction) async {
        await sendMessage(action.rawValue)
    }
}
