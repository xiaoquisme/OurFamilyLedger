import Foundation
import SwiftData

/// 分类模型
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String  // SF Symbol 名称
    var color: String
    var type: TransactionType  // 支出或收入分类
    var isDefault: Bool  // 是否为系统默认分类
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tag",
        color: String = "blue",
        type: TransactionType = .expense,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.type = type
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 默认支出分类
enum DefaultExpenseCategory: String, CaseIterable {
    case food = "餐饮"
    case shopping = "购物"
    case transport = "交通"
    case entertainment = "娱乐"
    case housing = "住房"
    case utilities = "水电"
    case medical = "医疗"
    case education = "教育"
    case childcare = "育儿"
    case travel = "旅行"
    case digital = "数码"
    case clothing = "服饰"
    case gift = "礼物"
    case other = "其他"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .shopping: return "cart"
        case .transport: return "car"
        case .entertainment: return "gamecontroller"
        case .housing: return "house"
        case .utilities: return "bolt"
        case .medical: return "cross.case"
        case .education: return "book"
        case .childcare: return "figure.and.child.holdinghands"
        case .travel: return "airplane"
        case .digital: return "desktopcomputer"
        case .clothing: return "tshirt"
        case .gift: return "gift"
        case .other: return "ellipsis.circle"
        }
    }

    var color: String {
        switch self {
        case .food: return "orange"
        case .shopping: return "pink"
        case .transport: return "blue"
        case .entertainment: return "purple"
        case .housing: return "brown"
        case .utilities: return "yellow"
        case .medical: return "red"
        case .education: return "green"
        case .childcare: return "mint"
        case .travel: return "cyan"
        case .digital: return "indigo"
        case .clothing: return "teal"
        case .gift: return "red"
        case .other: return "gray"
        }
    }

    func toCategory(sortOrder: Int) -> Category {
        Category(
            name: self.rawValue,
            icon: self.icon,
            color: self.color,
            type: .expense,
            isDefault: true,
            sortOrder: sortOrder
        )
    }
}

/// 默认收入分类
enum DefaultIncomeCategory: String, CaseIterable {
    case salary = "工资"
    case bonus = "奖金"
    case investment = "投资"
    case partTime = "兼职"
    case redPacket = "红包"
    case refund = "退款"
    case other = "其他收入"

    var icon: String {
        switch self {
        case .salary: return "briefcase"
        case .bonus: return "star"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .partTime: return "clock"
        case .redPacket: return "envelope"
        case .refund: return "arrow.uturn.backward"
        case .other: return "plus.circle"
        }
    }

    var color: String {
        switch self {
        case .salary: return "green"
        case .bonus: return "yellow"
        case .investment: return "blue"
        case .partTime: return "orange"
        case .redPacket: return "red"
        case .refund: return "gray"
        case .other: return "teal"
        }
    }

    func toCategory(sortOrder: Int) -> Category {
        Category(
            name: self.rawValue,
            icon: self.icon,
            color: self.color,
            type: .income,
            isDefault: true,
            sortOrder: sortOrder
        )
    }
}

/// CSV 导出/导入用的分类数据结构
struct CategoryCSV: Codable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let type: String
    let isDefault: String
    let sortOrder: String
    let createdAt: String
    let updatedAt: String

    static let headers = [
        "id", "name", "icon", "color", "type",
        "is_default", "sort_order", "created_at", "updated_at"
    ]
}
