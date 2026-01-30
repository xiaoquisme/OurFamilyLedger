# 确认对话框修复说明

## 问题描述
在记账页面弹出的用户确认框没有显示类别

## 问题分析
原始代码中，点击"全部确认"按钮时，直接调用 `viewModel.confirmAllDrafts()` 方法确认所有待处理的交易，**没有显示任何确认对话框**。

## 解决方案
在 `ChatView.swift` 中添加了一个确认对话框（`confirmationDialog`），当用户点击"全部确认"按钮时：

1. 显示一个确认对话框
2. 对话框标题："确认入账"
3. 对话框内容显示：
   - 每笔交易的类别和金额（格式：`• 类别名: ¥金额`）
   - 所有交易的总金额
4. 提供两个按钮：
   - "确认全部 N 笔交易" - 确认所有待处理的交易
   - "取消" - 取消操作

## 代码变更

### 1. 添加状态变量
```swift
// 确认对话框
@State private var showingConfirmAllDialog = false
```

### 2. 修改"全部确认"按钮行为
```swift
Button("全部确认") {
    showingConfirmAllDialog = true  // 显示对话框，而不是直接确认
}
```

### 3. 添加确认对话框
```swift
.confirmationDialog(
    "确认入账",
    isPresented: $showingConfirmAllDialog,
    presenting: viewModel.pendingDrafts
) { drafts in
    Button("确认全部 \(drafts.count) 笔交易") {
        Task {
            await viewModel.confirmAllDrafts()
        }
    }
    Button("取消", role: .cancel) {}
} message: { drafts in
    let summary = drafts.map { draft in
        "• \(draft.categoryName): \(draft.amount.formatted(currency: "CNY"))"
    }.joined(separator: "\n")
    
    let total = drafts.reduce(Decimal.zero) { $0 + $1.amount }
    let totalText = "\n\n总计: \(total.formatted(currency: "CNY"))"
    
    Text(summary + totalText)
}
```

## 用户体验改进

### 修复前
1. 用户点击"全部确认"
2. ❌ 直接确认所有交易，没有任何提示
3. ❌ 用户无法查看即将确认的交易详情
4. ❌ 误操作无法撤销

### 修复后
1. 用户点击"全部确认"
2. ✅ 显示确认对话框
3. ✅ 对话框中显示每笔交易的**类别**和金额
4. ✅ 显示总金额
5. ✅ 用户可以选择"确认"或"取消"
6. ✅ 提供了二次确认的机会，避免误操作

## 示例对话框内容

假设有3笔待确认的交易：
- 餐饮: ¥50.00
- 交通: ¥15.00  
- 购物: ¥120.00

对话框将显示：
```
确认入账

• 餐饮: ¥50.00
• 交通: ¥15.00
• 购物: ¥120.00

总计: ¥185.00

[确认全部 3 笔交易]  [取消]
```

## 测试建议

1. 创建多笔待确认的交易
2. 点击"全部确认"按钮
3. 验证对话框是否正确显示
4. 验证对话框中是否显示了所有交易的类别和金额
5. 验证总金额计算是否正确
6. 测试"确认"按钮是否正常工作
7. 测试"取消"按钮是否正常工作

## 影响范围

- ✅ 仅修改 UI 层，不影响业务逻辑
- ✅ 不需要修改 ViewModel 或数据模型
- ✅ 向后兼容，不会破坏现有功能
- ✅ 符合 iOS 原生设计规范
