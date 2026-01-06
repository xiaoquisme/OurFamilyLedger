import Foundation
import UIKit

/// AI 服务错误
enum AIServiceError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case parseError(String)
    case rateLimited
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "未配置 API Key"
        case .invalidResponse:
            return "AI 响应格式无效"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .parseError(let message):
            return "解析错误: \(message)"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .unauthorized:
            return "API Key 无效或已过期"
        }
    }
}

/// AI 服务协议
protocol AIServiceProtocol {
    /// 从文本解析交易
    func parseTransaction(from text: String) async throws -> [TransactionDraft]

    /// 从图片和 OCR 文本解析交易
    func parseTransaction(from image: UIImage, ocrText: String?) async throws -> [TransactionDraft]

    /// 测试 API 连接
    func testConnection() async throws -> Bool
}

/// AI 提供商
enum AIProvider: String, CaseIterable, Codable {
    case openai = "openai"
    case claude = "claude"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .custom: return "自定义"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-3-5-sonnet-20241022"
        case .custom: return ""
        }
    }
}

/// AI 服务配置
struct AIServiceConfig {
    let provider: AIProvider
    let apiKey: String
    let endpoint: String
    let model: String
    let temperature: Double

    init(
        provider: AIProvider,
        apiKey: String,
        endpoint: String? = nil,
        model: String? = nil,
        temperature: Double = 0.1
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.endpoint = endpoint ?? provider.defaultEndpoint
        self.model = model ?? provider.defaultModel
        self.temperature = temperature
    }
}

/// 交易解析提示词
struct TransactionParsePrompt {
    static let systemPrompt = """
    你是一个家庭记账助手，帮助用户从文字描述或截图文本中提取交易信息。

    请从输入内容中提取以下信息并以 JSON 格式返回：
    - date: 交易日期 (ISO 8601 格式，如果无法确定则使用今天)
    - amount: 金额 (数字)
    - type: 类型 ("expense" 支出 或 "income" 收入)
    - category: 分类 (如：餐饮、购物、交通等)
    - payer: 付款人 (如果无法确定则为空)
    - participants: 参与人列表 (如果无法确定则为空数组)
    - note: 备注
    - merchant: 商户名称 (如果有)
    - confidence_amount: 金额识别置信度 (0-1)
    - confidence_date: 日期识别置信度 (0-1)

    如果输入包含多笔交易，请返回一个数组。

    返回格式示例:
    ```json
    [
      {
        "date": "2024-01-15",
        "amount": 128.50,
        "type": "expense",
        "category": "餐饮",
        "payer": "我",
        "participants": ["我", "老婆"],
        "note": "晚餐",
        "merchant": "海底捞",
        "confidence_amount": 0.95,
        "confidence_date": 0.8
      }
    ]
    ```

    只返回 JSON，不要其他文字。
    """

    static func userPrompt(for text: String) -> String {
        "请从以下内容中提取交易信息:\n\n\(text)"
    }
}

/// AI 解析结果
struct AIParseResult: Codable {
    let date: String?
    let amount: Double
    let type: String
    let category: String
    let payer: String?
    let participants: [String]?
    let note: String?
    let merchant: String?
    let confidenceAmount: Double?
    let confidenceDate: Double?

    enum CodingKeys: String, CodingKey {
        case date, amount, type, category, payer, participants, note, merchant
        case confidenceAmount = "confidence_amount"
        case confidenceDate = "confidence_date"
    }

    func toTransactionDraft(source: TransactionSource) -> TransactionDraft {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let parsedDate: Date
        if let dateString = date, let date = dateFormatter.date(from: dateString) {
            parsedDate = date
        } else {
            parsedDate = Date()
        }

        let transactionType: TransactionType = type == "income" ? .income : .expense

        return TransactionDraft(
            date: parsedDate,
            amount: Decimal(amount),
            type: transactionType,
            categoryName: category,
            payerName: payer ?? "",
            participantNames: participants ?? [],
            note: note ?? "",
            merchant: merchant ?? "",
            source: source,
            confidenceAmount: confidenceAmount,
            confidenceDate: confidenceDate
        )
    }
}
