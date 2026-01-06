import Foundation
import SwiftData

/// 账本模型
@Model
final class Ledger {
    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String
    var defaultSplitAll: Bool  // 默认是否全家分摊
    var iCloudFolderPath: String?  // iCloud 共享文件夹路径
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "家庭账本",
        currency: String = "CNY",
        defaultSplitAll: Bool = true,
        iCloudFolderPath: String? = nil,
        isShared: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.currency = currency
        self.defaultSplitAll = defaultSplitAll
        self.iCloudFolderPath = iCloudFolderPath
        self.isShared = isShared
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 账本设置（存储为 JSON）
struct LedgerSettings: Codable {
    var currency: String
    var defaultSplitAll: Bool
    var defaultParticipantIds: [String]?
    var schemaVersion: Int

    static let currentSchemaVersion = 1

    init(
        currency: String = "CNY",
        defaultSplitAll: Bool = true,
        defaultParticipantIds: [String]? = nil
    ) {
        self.currency = currency
        self.defaultSplitAll = defaultSplitAll
        self.defaultParticipantIds = defaultParticipantIds
        self.schemaVersion = Self.currentSchemaVersion
    }
}

/// 支持的货币
enum SupportedCurrency: String, CaseIterable {
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case hkd = "HKD"
    case twd = "TWD"
    case gbp = "GBP"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        case .eur: return "€"
        case .jpy: return "¥"
        case .hkd: return "HK$"
        case .twd: return "NT$"
        case .gbp: return "£"
        }
    }

    var displayName: String {
        switch self {
        case .cny: return "人民币 (CNY)"
        case .usd: return "美元 (USD)"
        case .eur: return "欧元 (EUR)"
        case .jpy: return "日元 (JPY)"
        case .hkd: return "港币 (HKD)"
        case .twd: return "新台币 (TWD)"
        case .gbp: return "英镑 (GBP)"
        }
    }
}
