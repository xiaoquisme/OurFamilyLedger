import Foundation
import UIKit

/// OpenAI 兼容的 AI 服务实现
final class OpenAIService: AIServiceProtocol {
    private let config: AIServiceConfig
    private let session: URLSession

    init(config: AIServiceConfig) {
        self.config = config
        self.session = URLSession.shared
    }

    // MARK: - AIServiceProtocol

    func parseTransaction(from text: String) async throws -> [TransactionDraft] {
        let messages: [[String: Any]] = [
            ["role": "system", "content": TransactionParsePrompt.systemPrompt],
            ["role": "user", "content": TransactionParsePrompt.userPrompt(for: text)]
        ]

        let responseContent = try await sendChatRequest(messages: messages)
        return try parseResponse(responseContent, source: .text)
    }

    func parseTransaction(from image: UIImage, ocrText: String?) async throws -> [TransactionDraft] {
        var content: [[String: Any]] = []

        // 添加图片（如果支持视觉模型）
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            let base64Image = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64Image)"
                ]
            ])
        }

        // 添加 OCR 文本（如果有）
        var textPrompt = TransactionParsePrompt.userPrompt(for: "")
        if let ocrText = ocrText, !ocrText.isEmpty {
            textPrompt = TransactionParsePrompt.userPrompt(for: "OCR 识别文本:\n\(ocrText)")
        } else {
            textPrompt = "请从图片中识别并提取交易信息"
        }

        content.append([
            "type": "text",
            "text": textPrompt
        ])

        let messages: [[String: Any]] = [
            ["role": "system", "content": TransactionParsePrompt.systemPrompt],
            ["role": "user", "content": content]
        ]

        let responseContent = try await sendChatRequest(messages: messages)
        let source: TransactionSource = ocrText != nil ? .appleOCR : .visionModel
        return try parseResponse(responseContent, source: source)
    }

    func testConnection() async throws -> Bool {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "Hello"]
        ]

        _ = try await sendChatRequest(messages: messages)
        return true
    }

    func fetchModels() async throws -> [AIModel] {
        guard !config.apiKey.isEmpty else {
            throw AIServiceError.noAPIKey
        }

        let url = URL(string: "\(config.endpoint)/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

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

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["data"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        var models: [AIModel] = []
        for modelData in modelsData {
            if let id = modelData["id"] as? String {
                let ownedBy = modelData["owned_by"] as? String
                models.append(AIModel(id: id, ownedBy: ownedBy))
            }
        }

        // 按 ID 排序，优先显示常用模型
        return models.sorted { m1, m2 in
            let priority1 = modelPriority(m1.id)
            let priority2 = modelPriority(m2.id)
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return m1.id < m2.id
        }
    }

    /// 模型优先级（数字越小越靠前）
    private func modelPriority(_ modelId: String) -> Int {
        if modelId.contains("gpt-4o") { return 1 }
        if modelId.contains("gpt-4") { return 2 }
        if modelId.contains("gpt-3.5") { return 3 }
        if modelId.contains("claude") { return 4 }
        return 100
    }

    // MARK: - Private

    private func sendChatRequest(messages: [[String: Any]]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw AIServiceError.noAPIKey
        }

        let url = URL(string: "\(config.endpoint)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": config.temperature,
            "max_tokens": 2000
        ]

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

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }

        return content
    }

    private func parseResponse(_ content: String, source: TransactionSource) throws -> [TransactionDraft] {
        // 提取 JSON（可能被 markdown 包裹）
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除 markdown 代码块
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: "\n")
            let filtered = lines.dropFirst().dropLast()
            jsonString = filtered.joined(separator: "\n")
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIServiceError.parseError("无法解析响应")
        }

        let decoder = JSONDecoder()

        // 尝试解析为数组
        if let results = try? decoder.decode([AIParseResult].self, from: jsonData) {
            return results.map { $0.toTransactionDraft(source: source) }
        }

        // 尝试解析为单个对象
        if let result = try? decoder.decode(AIParseResult.self, from: jsonData) {
            return [result.toTransactionDraft(source: source)]
        }

        throw AIServiceError.parseError("JSON 格式无效")
    }
}

// MARK: - AI Service Factory

final class AIServiceFactory {
    static func create(provider: AIProvider, apiKey: String, endpoint: String? = nil, model: String? = nil) -> AIServiceProtocol {
        let config = AIServiceConfig(
            provider: provider,
            apiKey: apiKey,
            endpoint: endpoint,
            model: model
        )

        switch provider {
        case .openai, .custom:
            return OpenAIService(config: config)
        case .claude:
            // Claude 使用 OpenAI 兼容接口
            return OpenAIService(config: config)
        }
    }
}
