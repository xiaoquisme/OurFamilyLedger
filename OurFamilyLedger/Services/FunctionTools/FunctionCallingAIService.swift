import Foundation
import SwiftData

/// 支持 Function Calling 的 AI 聊天服务
@MainActor
final class FunctionCallingAIService {
    private let config: AIServiceConfig
    private let session: URLSession
    private let functionToolsService: FunctionToolsService

    /// 系统提示词（动态生成，包含当前日期）
    private var systemPrompt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: Date())

        return """
        你是家庭记账助手，帮助用户管理家庭财务。

        当前日期：\(today)（\(year)年\(month)月）

        你可以：
        1. 记账：添加收入和支出记录
        2. 查询：搜索和查看交易历史
        3. 报表：生成月度收支统计
        4. 管理：管理分类、成员、提醒等

        工具使用指南：
        - 记账时使用 add_transaction，日期格式为 YYYY-MM-DD
        - 查看交易时使用 list_transactions，可传入 startDate 和 endDate 筛选
        - 查看"今天的交易"时，startDate 和 endDate 都传入今天的日期 \(today)
        - 查看统计时使用 get_monthly_summary、get_category_breakdown 等

        请使用中文回复用户，语气友好自然。
        执行工具后，用简洁的语言总结操作结果。
        如果用户只是闲聊，不需要调用工具，直接回复即可。
        """
    }

    init(config: AIServiceConfig, modelContext: ModelContext) {
        self.config = config
        self.session = URLSession.shared
        self.functionToolsService = FunctionToolsService(modelContext: modelContext)
    }

    /// 聊天消息结构
    struct ChatMessage {
        enum Role: String {
            case system
            case user
            case assistant
            case tool
        }

        let role: Role
        let content: String?
        let toolCalls: [ToolCall]?
        let toolCallId: String?
        let name: String?

        init(role: Role, content: String) {
            self.role = role
            self.content = content
            self.toolCalls = nil
            self.toolCallId = nil
            self.name = nil
        }

        init(toolResult: String, toolCallId: String, name: String) {
            self.role = .tool
            self.content = toolResult
            self.toolCalls = nil
            self.toolCallId = toolCallId
            self.name = name
        }

        init(assistantWithToolCalls toolCalls: [ToolCall], content: String? = nil) {
            self.role = .assistant
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallId = nil
            self.name = nil
        }

        func toDict() -> [String: Any] {
            var dict: [String: Any] = ["role": role.rawValue]

            if let content = content {
                dict["content"] = content
            }

            if let toolCalls = toolCalls {
                dict["tool_calls"] = toolCalls.map { $0.toDict() }
            }

            if let toolCallId = toolCallId {
                dict["tool_call_id"] = toolCallId
            }

            if let name = name {
                dict["name"] = name
            }

            return dict
        }
    }

    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall

        func toDict() -> [String: Any] {
            [
                "id": id,
                "type": type,
                "function": [
                    "name": function.name,
                    "arguments": function.arguments
                ]
            ]
        }
    }

    /// 聊天响应
    struct ChatResponse {
        let content: String?
        let toolCalls: [ToolCall]?
        let finishReason: String?
    }

    /// 发送聊天消息并处理 function calling
    func chat(
        userMessage: String,
        conversationHistory: [ChatMessage] = []
    ) async throws -> String {
        var messages = conversationHistory

        // 添加系统消息（如果是新对话）
        if messages.isEmpty || messages.first?.role != .system {
            messages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
        }

        // 添加用户消息
        messages.append(ChatMessage(role: .user, content: userMessage))

        // 循环处理直到获得最终响应
        var maxIterations = 10  // 防止无限循环
        var iteration = 0

        while iteration < maxIterations {
            iteration += 1

            let response = try await sendChatRequest(messages: messages)

            // 如果有 tool calls，执行它们
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // 添加 assistant 消息（包含 tool calls）
                messages.append(ChatMessage(assistantWithToolCalls: toolCalls, content: response.content))

                // 执行每个 tool call 并添加结果
                for toolCall in toolCalls {
                    let result = await functionToolsService.execute(toolCall.function)
                    messages.append(ChatMessage(
                        toolResult: result.jsonString,
                        toolCallId: toolCall.id,
                        name: toolCall.function.name
                    ))
                }

                // 继续循环，让 AI 处理工具结果
                continue
            }

            // 没有 tool calls，返回最终响应
            if let content = response.content {
                return content
            }

            // 没有内容也没有 tool calls
            return "抱歉，我没有理解您的意思。"
        }

        return "处理请求时遇到问题，请重试。"
    }

    /// 发送单次 API 请求
    private func sendChatRequest(messages: [ChatMessage]) async throws -> ChatResponse {
        guard !config.apiKey.isEmpty else {
            throw AIServiceError.noAPIKey
        }

        let url = URL(string: "\(config.endpoint)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { $0.toDict() },
            "temperature": config.temperature,
            "max_tokens": 2000,
            "tools": FunctionTool.allDefinitions
        ]

        // Claude API 特殊处理
        if config.provider == .claude {
            // Claude 使用不同的 tools 格式
            body["tools"] = FunctionTool.allCases.map { tool in
                [
                    "name": tool.rawValue,
                    "description": tool.description,
                    "input_schema": tool.parameters
                ]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw AIServiceError.unauthorized
        case 429:
            throw AIServiceError.rateLimited
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.parseError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> ChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let content = message["content"] as? String
        let finishReason = firstChoice["finish_reason"] as? String

        var toolCalls: [ToolCall]? = nil

        if let toolCallsData = message["tool_calls"] as? [[String: Any]] {
            toolCalls = try toolCallsData.map { tcData in
                guard let id = tcData["id"] as? String,
                      let type = tcData["type"] as? String,
                      let functionData = tcData["function"] as? [String: Any],
                      let name = functionData["name"] as? String,
                      let arguments = functionData["arguments"] as? String else {
                    throw AIServiceError.parseError("无法解析 tool_call")
                }

                return ToolCall(
                    id: id,
                    type: type,
                    function: FunctionCall(name: name, arguments: arguments)
                )
            }
        }

        return ChatResponse(
            content: content,
            toolCalls: toolCalls,
            finishReason: finishReason
        )
    }
}

// MARK: - 对话历史管理

extension FunctionCallingAIService {
    /// 简化的对话入口
    func sendMessage(_ text: String) async throws -> String {
        try await chat(userMessage: text)
    }
}
