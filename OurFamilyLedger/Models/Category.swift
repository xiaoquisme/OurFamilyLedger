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
    case daily = "日用"
    case transport = "交通"
    case vegetable = "蔬菜"
    case fruit = "水果"
    case snack = "零食"
    case sports = "运动"
    case entertainment = "娱乐"
    case communication = "通讯"
    case clothing = "服饰"
    case beauty = "美容"
    case housing = "住房"
    case home = "居家"
    case children = "孩子"
    case elders = "长辈"
    case social = "社交"
    case travel = "旅行"
    case alcohol = "烟酒"
    case digital = "数码"
    case car = "汽车"
    case medical = "医疗"
    case books = "书籍"
    case education = "学习"
    case pet = "宠物"
    case cashGift = "礼金"
    case gift = "礼物"
    case office = "办公"
    case repair = "维修"
    case donation = "捐赠"
    case lottery = "彩票"
    case relatives = "亲友"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .shopping: return "bag"
        case .daily: return "toilet.fill"
        case .transport: return "bus"
        case .vegetable: return "carrot"
        case .fruit: return "leaf"
        case .snack: return "birthday.cake"
        case .sports: return "bicycle"
        case .entertainment: return "music.mic"
        case .communication: return "phone"
        case .clothing: return "tshirt"
        case .beauty: return "paintbrush"
        case .housing: return "house"
        case .home: return "sofa"
        case .children: return "figure.2.and.child.holdinghands"
        case .elders: return "figure.walk"
        case .social: return "bubble.left.and.bubble.right"
        case .travel: return "airplane"
        case .alcohol: return "wineglass"
        case .digital: return "cable.connector"
        case .car: return "car"
        case .medical: return "cross.case"
        case .books: return "book"
        case .education: return "graduationcap"
        case .pet: return "pawprint"
        case .cashGift: return "yensign.circle"
        case .gift: return "gift"
        case .office: return "briefcase"
        case .repair: return "wrench"
        case .donation: return "heart"
        case .lottery: return "ticket"
        case .relatives: return "person.3"
        }
    }

    var color: String {
        "gray"  // 默认使用灰色，选中时使用黄色
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
    case partTime = "兼职"
    case investment = "理财"
    case cashGift = "礼金"
    case other = "其它"

    var icon: String {
        switch self {
        case .salary: return "yensign.square"
        case .partTime: return "clock.badge.checkmark"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .cashGift: return "dollarsign.square"
        case .other: return "bag"
        }
    }

    var color: String {
        "gray"  // 默认使用灰色，选中时使用黄色
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
