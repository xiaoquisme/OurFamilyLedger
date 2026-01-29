import Foundation

// MARK: - Function Tool 定义

/// AI 可调用的 Function Tool 定义
enum FunctionTool: String, CaseIterable, Codable {
    // 交易相关
    case addTransaction = "add_transaction"
    case listTransactions = "list_transactions"
    case getTransaction = "get_transaction"
    case updateTransaction = "update_transaction"
    case deleteTransaction = "delete_transaction"
    case searchTransactions = "search_transactions"

    // 分类相关
    case listCategories = "list_categories"
    case addCategory = "add_category"
    case updateCategory = "update_category"
    case deleteCategory = "delete_category"

    // 成员相关
    case listMembers = "list_members"
    case addMember = "add_member"
    case updateMember = "update_member"
    case deleteMember = "delete_member"
    case setDefaultMember = "set_default_member"

    // 报表相关
    case getMonthlySummary = "get_monthly_summary"
    case getCategoryBreakdown = "get_category_breakdown"
    case getMemberBreakdown = "get_member_breakdown"

    // 提醒相关
    case listReminders = "list_reminders"
    case addReminder = "add_reminder"
    case updateReminder = "update_reminder"
    case deleteReminder = "delete_reminder"

    // 定期交易相关
    case listRecurringTransactions = "list_recurring_transactions"
    case addRecurringTransaction = "add_recurring_transaction"
    case updateRecurringTransaction = "update_recurring_transaction"
    case deleteRecurringTransaction = "delete_recurring_transaction"

    // 数据管理
    case exportData = "export_data"
    case getICloudStatus = "get_icloud_status"
    case syncData = "sync_data"

    /// 获取 OpenAI Function Calling 格式的定义
    var definition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": rawValue,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    var description: String {
        switch self {
        // 交易
        case .addTransaction:
            return "添加一笔新的交易记录。可以是支出或收入。"
        case .listTransactions:
            return "获取交易列表。可按日期范围、分类、成员筛选。"
        case .getTransaction:
            return "根据ID获取单笔交易的详细信息。"
        case .updateTransaction:
            return "更新已有交易的信息。"
        case .deleteTransaction:
            return "删除指定的交易记录。"
        case .searchTransactions:
            return "搜索交易记录。支持按备注、商户名称等关键词搜索。"

        // 分类
        case .listCategories:
            return "获取所有交易分类列表，包括支出和收入分类。"
        case .addCategory:
            return "添加新的自定义分类。"
        case .updateCategory:
            return "更新分类信息。"
        case .deleteCategory:
            return "删除自定义分类。"

        // 成员
        case .listMembers:
            return "获取家庭成员列表。"
        case .addMember:
            return "添加新的家庭成员。"
        case .updateMember:
            return "更新成员信息。"
        case .deleteMember:
            return "删除家庭成员。"
        case .setDefaultMember:
            return "设置默认付款人。"

        // 报表
        case .getMonthlySummary:
            return "获取指定月份的收支概览，包括总收入、总支出、结余。"
        case .getCategoryBreakdown:
            return "获取指定月份按分类统计的支出/收入明细。"
        case .getMemberBreakdown:
            return "获取指定月份按成员统计的支出明细。"

        // 提醒
        case .listReminders:
            return "获取所有记账提醒。"
        case .addReminder:
            return "添加新的记账提醒。"
        case .updateReminder:
            return "更新提醒设置。"
        case .deleteReminder:
            return "删除提醒。"

        // 定期交易
        case .listRecurringTransactions:
            return "获取所有定期交易模板。"
        case .addRecurringTransaction:
            return "创建新的定期交易模板。"
        case .updateRecurringTransaction:
            return "更新定期交易设置。"
        case .deleteRecurringTransaction:
            return "删除定期交易模板。"

        // 数据管理
        case .exportData:
            return "导出数据为CSV格式。"
        case .getICloudStatus:
            return "获取iCloud同步状态。"
        case .syncData:
            return "手动触发数据同步。"
        }
    }

    var parameters: [String: Any] {
        switch self {
        // 交易
        case .addTransaction:
            return [
                "type": "object",
                "properties": [
                    "amount": ["type": "number", "description": "金额（正数）"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "交易类型：expense(支出)或income(收入)"],
                    "category": ["type": "string", "description": "分类名称，如：餐饮、购物、工资等"],
                    "date": ["type": "string", "description": "日期，格式：YYYY-MM-DD，不填则使用今天"],
                    "note": ["type": "string", "description": "备注说明"],
                    "merchant": ["type": "string", "description": "商户名称"],
                    "payer": ["type": "string", "description": "付款人名称"],
                    "participants": ["type": "array", "items": ["type": "string"], "description": "参与人名称列表（用于分摊）"]
                ],
                "required": ["amount", "type", "category"]
            ]

        case .listTransactions:
            return [
                "type": "object",
                "properties": [
                    "startDate": ["type": "string", "description": "起始日期，格式：YYYY-MM-DD"],
                    "endDate": ["type": "string", "description": "结束日期，格式：YYYY-MM-DD"],
                    "category": ["type": "string", "description": "分类名称筛选"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "交易类型筛选"],
                    "member": ["type": "string", "description": "成员名称筛选"],
                    "limit": ["type": "integer", "description": "返回数量限制，默认20"]
                ]
            ]

        case .getTransaction:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "交易ID"]
                ],
                "required": ["id"]
            ]

        case .updateTransaction:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "交易ID"],
                    "amount": ["type": "number", "description": "新金额"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "新交易类型"],
                    "category": ["type": "string", "description": "新分类名称"],
                    "date": ["type": "string", "description": "新日期"],
                    "note": ["type": "string", "description": "新备注"],
                    "merchant": ["type": "string", "description": "新商户名称"],
                    "payer": ["type": "string", "description": "新付款人"],
                    "participants": ["type": "array", "items": ["type": "string"], "description": "新参与人列表"]
                ],
                "required": ["id"]
            ]

        case .deleteTransaction:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "要删除的交易ID"]
                ],
                "required": ["id"]
            ]

        case .searchTransactions:
            return [
                "type": "object",
                "properties": [
                    "keyword": ["type": "string", "description": "搜索关键词"],
                    "limit": ["type": "integer", "description": "返回数量限制，默认20"]
                ],
                "required": ["keyword"]
            ]

        // 分类
        case .listCategories:
            return [
                "type": "object",
                "properties": [
                    "type": ["type": "string", "enum": ["expense", "income", "all"], "description": "分类类型筛选，默认all"]
                ]
            ]

        case .addCategory:
            return [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "分类名称"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "分类类型"],
                    "icon": ["type": "string", "description": "SF Symbol图标名称"],
                    "color": ["type": "string", "description": "颜色名称"]
                ],
                "required": ["name", "type"]
            ]

        case .updateCategory:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "分类ID"],
                    "name": ["type": "string", "description": "新名称"],
                    "icon": ["type": "string", "description": "新图标"],
                    "color": ["type": "string", "description": "新颜色"]
                ],
                "required": ["id"]
            ]

        case .deleteCategory:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "分类ID"]
                ],
                "required": ["id"]
            ]

        // 成员
        case .listMembers:
            return ["type": "object", "properties": [:]]

        case .addMember:
            return [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "成员名称"],
                    "nickname": ["type": "string", "description": "昵称"],
                    "role": ["type": "string", "enum": ["admin", "member"], "description": "角色，默认member"],
                    "avatarColor": ["type": "string", "description": "头像颜色"]
                ],
                "required": ["name"]
            ]

        case .updateMember:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "成员ID"],
                    "name": ["type": "string", "description": "新名称"],
                    "nickname": ["type": "string", "description": "新昵称"],
                    "avatarColor": ["type": "string", "description": "新头像颜色"]
                ],
                "required": ["id"]
            ]

        case .deleteMember:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "成员ID"]
                ],
                "required": ["id"]
            ]

        case .setDefaultMember:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "成员ID"],
                    "name": ["type": "string", "description": "成员名称（与ID二选一）"]
                ]
            ]

        // 报表
        case .getMonthlySummary:
            return [
                "type": "object",
                "properties": [
                    "year": ["type": "integer", "description": "年份，默认当前年"],
                    "month": ["type": "integer", "description": "月份(1-12)，默认当前月"]
                ]
            ]

        case .getCategoryBreakdown:
            return [
                "type": "object",
                "properties": [
                    "year": ["type": "integer", "description": "年份"],
                    "month": ["type": "integer", "description": "月份(1-12)"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "统计类型，默认expense"]
                ]
            ]

        case .getMemberBreakdown:
            return [
                "type": "object",
                "properties": [
                    "year": ["type": "integer", "description": "年份"],
                    "month": ["type": "integer", "description": "月份(1-12)"]
                ]
            ]

        // 提醒
        case .listReminders:
            return ["type": "object", "properties": [:]]

        case .addReminder:
            return [
                "type": "object",
                "properties": [
                    "hour": ["type": "integer", "description": "小时(0-23)"],
                    "minute": ["type": "integer", "description": "分钟(0-59)"],
                    "message": ["type": "string", "description": "提醒消息"],
                    "frequency": ["type": "string", "enum": ["daily", "monthly"], "description": "频率，默认daily"]
                ],
                "required": ["hour", "minute"]
            ]

        case .updateReminder:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "提醒ID"],
                    "hour": ["type": "integer", "description": "新小时"],
                    "minute": ["type": "integer", "description": "新分钟"],
                    "message": ["type": "string", "description": "新消息"],
                    "isEnabled": ["type": "boolean", "description": "是否启用"]
                ],
                "required": ["id"]
            ]

        case .deleteReminder:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "提醒ID"]
                ],
                "required": ["id"]
            ]

        // 定期交易
        case .listRecurringTransactions:
            return ["type": "object", "properties": [:]]

        case .addRecurringTransaction:
            return [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "名称/备注"],
                    "amount": ["type": "number", "description": "金额"],
                    "type": ["type": "string", "enum": ["expense", "income"], "description": "交易类型"],
                    "category": ["type": "string", "description": "分类名称"],
                    "frequency": ["type": "string", "enum": ["daily", "weekly", "monthly", "yearly"], "description": "频率"],
                    "interval": ["type": "integer", "description": "间隔（每N天/周/月/年）"],
                    "weekday": ["type": "integer", "description": "星期几(0-6)，weekly时使用"],
                    "weekdays": ["type": "array", "items": ["type": "integer"], "description": "星期几列表(0-6)，weekly时使用"],
                    "dayOfMonth": ["type": "integer", "description": "每月/年几号(1-31)"],
                    "monthOfYear": ["type": "integer", "description": "月份(1-12)，yearly时使用"],
                    "autoAdd": ["type": "boolean", "description": "是否自动添加"],
                    "payer": ["type": "string", "description": "付款人"],
                    "merchant": ["type": "string", "description": "商户"]
                ],
                "required": ["name", "amount", "type", "category", "frequency"]
            ]

        case .updateRecurringTransaction:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "定期交易ID"],
                    "name": ["type": "string", "description": "新名称"],
                    "amount": ["type": "number", "description": "新金额"],
                    "isEnabled": ["type": "boolean", "description": "是否启用"]
                ],
                "required": ["id"]
            ]

        case .deleteRecurringTransaction:
            return [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "定期交易ID"]
                ],
                "required": ["id"]
            ]

        // 数据管理
        case .exportData:
            return [
                "type": "object",
                "properties": [
                    "format": ["type": "string", "enum": ["csv"], "description": "导出格式，目前仅支持csv"]
                ]
            ]

        case .getICloudStatus:
            return ["type": "object", "properties": [:]]

        case .syncData:
            return ["type": "object", "properties": [:]]
        }
    }

    /// 获取所有 tools 定义（用于 API 调用）
    static var allDefinitions: [[String: Any]] {
        allCases.map { $0.definition }
    }
}

// MARK: - Function Call 请求/响应

/// AI 返回的 Function Call
struct FunctionCall: Codable {
    let name: String
    let arguments: String

    var tool: FunctionTool? {
        FunctionTool(rawValue: name)
    }

    func parseArguments<T: Decodable>() throws -> T {
        guard let data = arguments.data(using: .utf8) else {
            throw FunctionToolError.invalidArguments("无法解析参数")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Function Tool 执行结果
struct FunctionToolResult: Codable {
    let success: Bool
    let data: AnyCodable?
    let error: String?

    static func success(_ data: Any) -> FunctionToolResult {
        FunctionToolResult(success: true, data: AnyCodable(data), error: nil)
    }

    static func failure(_ error: String) -> FunctionToolResult {
        FunctionToolResult(success: false, data: nil, error: error)
    }

    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"success\": false, \"error\": \"编码失败\"}"
        }
        return string
    }
}

/// 用于包装任意 Codable 值
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Errors

enum FunctionToolError: LocalizedError {
    case invalidArguments(String)
    case notFound(String)
    case operationFailed(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "参数错误: \(msg)"
        case .notFound(let msg): return "未找到: \(msg)"
        case .operationFailed(let msg): return "操作失败: \(msg)"
        case .unauthorized(let msg): return "权限不足: \(msg)"
        }
    }
}
