# OurFamilyLedger

一款专为家庭设计的 iOS 记账应用，支持 AI 智能识别、多成员协作和 iCloud 同步。

## 功能特性

### 智能记账
- **文本记账** - 输入自然语言描述，AI 自动解析生成交易记录
- **截图识别** - 支持支付截图、小票 OCR 识别，自动提取金额和商户信息
- **多图批量** - 一次选择多张图片，批量识别生成多笔交易

### 家庭共享
- **多成员协作** - 通过 iCloud 文件夹共享，支持不同 Apple ID 的家庭成员
- **自动同步** - 数据实时同步，多设备无缝切换
- **冲突处理** - 智能检测并解决多人同时编辑的冲突

### 分类管理
- **丰富预设** - 32 种支出分类 + 5 种收入分类，覆盖日常生活场景
- **自定义分类** - 支持添加、编辑、删除分类
- **图标支持** - 每个分类配有直观的 SF Symbol 图标

### 数据管理
- **CSV 导出** - 数据可导出为 CSV 格式，便于电脑处理
- **按月存储** - 交易按月拆分文件，降低冲突概率
- **本地缓存** - SwiftData 本地缓存，快速查询

### AI 配置
- **多模型支持** - 支持 OpenAI、Claude 等多种 AI 提供商
- **自定义端点** - 支持配置自定义 API 端点
- **模型刷新** - 可获取可用模型列表并切换
- **安全存储** - API Key 使用 Keychain 安全存储

## 技术栈

- **iOS 版本**: iOS 17+
- **UI 框架**: SwiftUI
- **数据持久化**: SwiftData + CSV
- **架构模式**: MVVM
- **OCR**: Apple Vision Framework
- **AI 服务**: OpenAI API 兼容接口

## 项目结构

```
OurFamilyLedger/
├── App/
│   ├── OurFamilyLedgerApp.swift    # 应用入口
│   └── ContentView.swift            # 主导航
├── Models/
│   ├── Transaction.swift            # 交易模型
│   ├── Member.swift                 # 成员模型
│   ├── Category.swift               # 分类模型
│   └── Ledger.swift                 # 账本模型
├── ViewModels/
│   ├── ChatViewModel.swift          # 聊天记账逻辑
│   └── TransactionListViewModel.swift
├── Views/
│   ├── Chat/ChatView.swift          # 聊天记账界面
│   ├── Transactions/                # 交易明细
│   ├── Reports/                     # 报表统计
│   ├── Family/                      # 家庭管理
│   └── Settings/SettingsView.swift  # 设置
├── Services/
│   ├── AI/
│   │   ├── AIServiceProtocol.swift  # AI 服务协议
│   │   └── OpenAIService.swift      # OpenAI 实现
│   ├── OCR/
│   │   ├── OCRServiceProtocol.swift
│   │   └── AppleOCRService.swift    # Apple Vision OCR
│   ├── Storage/
│   │   ├── CSVService.swift         # CSV 读写
│   │   ├── iCloudService.swift      # iCloud 同步
│   │   └── ConflictResolver.swift   # 冲突处理
│   └── KeychainService.swift        # 密钥存储
└── Utilities/
    └── Extensions/                  # 扩展工具
```

## 快速开始

### 环境要求
- Xcode 15.0+
- iOS 17.0+
- macOS 14.0+

### 安装步骤

1. 克隆仓库
```bash
git clone https://github.com/xiaoquisme/OurFamilyLedger.git
cd OurFamilyLedger
```

2. 打开项目
```bash
open OurFamilyLedger.xcodeproj
```

3. 配置签名
   - 在 Xcode 中选择你的开发者团队
   - 确保 Bundle Identifier 唯一

4. 配置 iCloud（可选）
   - 在 Signing & Capabilities 中启用 iCloud
   - 勾选 CloudKit Documents

5. 运行项目
   - 选择目标设备或模拟器
   - 按 Cmd+R 运行

## 使用说明

### 首次使用
1. 打开应用，进入"设置"标签
2. 配置 AI 提供商和 API Key
3. 点击"测试连接"验证配置

### 记账流程
1. 进入"记账"标签
2. 输入文字描述或选择截图
3. AI 自动生成待确认卡片
4. 确认或编辑后入账

### 家庭共享
1. 进入"家庭"标签
2. 创建新账本或加入已有账本
3. 邀请家庭成员

## 默认分类

### 支出分类（32 种）
餐饮、购物、日用、交通、蔬菜、水果、零食、运动、娱乐、通讯、服饰、美容、住房、居家、孩子、长辈、社交、旅行、烟酒、数码、汽车、医疗、书籍、学习、宠物、礼金、礼物、办公、维修、捐赠、彩票、亲友

### 收入分类（5 种）
工资、兼职、理财、礼金、其它

## CSV 数据格式

交易记录 CSV 包含以下字段：
```
id, created_at, updated_at, date, amount, category, payer, participants, note, merchant, source
```

## 开发计划

- [x] Stage 1: 项目基础设施
- [x] Stage 2: 聊天记账核心功能
- [x] Stage 3: 账本明细与编辑
- [x] Stage 4: 家庭共享与 iCloud
- [x] Stage 5: 设置与 AI 配置
- [ ] Stage 6: 报表与预算（进行中）

## 许可证

MIT License - [https://github.com/xiaoquisme/OurFamilyLedger](https://github.com/xiaoquisme/OurFamilyLedger)

## 贡献

欢迎提交 [Issue](https://github.com/xiaoquisme/OurFamilyLedger/issues) 和 [Pull Request](https://github.com/xiaoquisme/OurFamilyLedger/pulls)！
