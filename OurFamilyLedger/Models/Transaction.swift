import Foundation
import SwiftData

/// 交易类型
enum TransactionType: String, Codable, CaseIterable {
    case expense = "支出"
    case income = "收入"
}

/// 交易来源
enum TransactionSource: String, Codable, CaseIterable {
    case text = "text"
    case appleOCR = "apple_ocr"
    case visionModel = "vision_model"
    case manual = "manual"
}

/// 交易记录模型（SwiftData）
@Model
final class TransactionRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var date: Date
    var amount: Decimal
    var type: TransactionType
    var categoryId: UUID?
    var payerId: UUID?
    var participantIds: [UUID]
    var note: String
    var merchant: String
    var source: TransactionSource
    var ocrText: String?
    var confidenceAmount: Double?
    var confidenceDate: Double?
    var currency: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        date: Date = Date(),
        amount: Decimal,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        payerId: UUID? = nil,
        participantIds: [UUID] = [],
        note: String = "",
        merchant: String = "",
        source: TransactionSource = .manual,
        ocrText: String? = nil,
        confidenceAmount: Double? = nil,
        confidenceDate: Double? = nil,
        currency: String = "CNY"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.amount = amount
        self.type = type
        self.categoryId = categoryId
        self.payerId = payerId
        self.participantIds = participantIds
        self.note = note
        self.merchant = merchant
        self.source = source
        self.ocrText = ocrText
        self.confidenceAmount = confidenceAmount
        self.confidenceDate = confidenceDate
        self.currency = currency
    }
}

/// 交易草稿（用于 AI 解析结果，未确认入账）
struct TransactionDraft: Identifiable, Equatable {
    let id: UUID
    var date: Date
    var amount: Decimal
    var type: TransactionType
    var categoryName: String
    var payerName: String
    var participantNames: [String]
    var note: String
    var merchant: String
    var source: TransactionSource
    var ocrText: String?
    var confidenceAmount: Double?
    var confidenceDate: Double?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        amount: Decimal,
        type: TransactionType = .expense,
        categoryName: String = "",
        payerName: String = "",
        participantNames: [String] = [],
        note: String = "",
        merchant: String = "",
        source: TransactionSource = .text,
        ocrText: String? = nil,
        confidenceAmount: Double? = nil,
        confidenceDate: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.type = type
        self.categoryName = categoryName
        self.payerName = payerName
        self.participantNames = participantNames
        self.note = note
        self.merchant = merchant
        self.source = source
        self.ocrText = ocrText
        self.confidenceAmount = confidenceAmount
        self.confidenceDate = confidenceDate
    }

    /// 计算每人应分摊金额
    var splitAmount: Decimal {
        guard !participantNames.isEmpty else { return amount }
        return amount / Decimal(participantNames.count)
    }
}

/// CSV 导出/导入用的交易数据结构
struct TransactionCSV: Codable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let date: String
    let amount: String
    let type: String
    let category: String
    let payer: String
    let participants: String  // 分号分隔
    let note: String
    let merchant: String
    let source: String
    let ocrText: String?
    let currency: String

    static let headers = [
        "id", "created_at", "updated_at", "date", "amount", "type",
        "category", "payer", "participants", "note", "merchant",
        "source", "ocr_text", "currency"
    ]
}
