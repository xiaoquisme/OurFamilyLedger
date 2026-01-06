import Foundation
import SwiftData

/// 成员角色
enum MemberRole: String, Codable, CaseIterable {
    case admin = "管理员"
    case member = "成员"

    var description: String {
        switch self {
        case .admin: return "可修改设置、导出数据、管理分类"
        case .member: return "可记账、查看、编辑交易"
        }
    }
}

/// 家庭成员模型
@Model
final class Member {
    @Attribute(.unique) var id: UUID
    var name: String
    var nickname: String
    var role: MemberRole
    var avatarColor: String  // 使用颜色名称作为头像背景
    var iCloudIdentifier: String?  // iCloud 身份标识
    var isCurrentUser: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        nickname: String = "",
        role: MemberRole = .member,
        avatarColor: String = "blue",
        iCloudIdentifier: String? = nil,
        isCurrentUser: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname.isEmpty ? name : nickname
        self.role = role
        self.avatarColor = avatarColor
        self.iCloudIdentifier = iCloudIdentifier
        self.isCurrentUser = isCurrentUser
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 显示名称（优先使用昵称）
    var displayName: String {
        nickname.isEmpty ? name : nickname
    }

    /// 头像首字母
    var initials: String {
        let name = displayName
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }
}

/// CSV 导出/导入用的成员数据结构
struct MemberCSV: Codable {
    let id: String
    let name: String
    let nickname: String
    let role: String
    let avatarColor: String
    let iCloudIdentifier: String?
    let createdAt: String
    let updatedAt: String

    static let headers = [
        "id", "name", "nickname", "role", "avatar_color",
        "icloud_identifier", "created_at", "updated_at"
    ]
}

/// 预设头像颜色
enum AvatarColor: String, CaseIterable {
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case yellow = "yellow"
    case teal = "teal"

    var displayName: String {
        switch self {
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .red: return "红色"
        case .yellow: return "黄色"
        case .teal: return "青色"
        }
    }
}
