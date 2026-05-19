# OurFamilyLedger CLI

家庭账本命令行工具，基于 SQLite 存储。从 iOS OurFamilyLedger 迁移而来。

## 安装

```bash
cd cli
pip install -e .
```

或使用 uvx（无需安装）：

```bash
cd cli
uvx --from . ledger --help
```

## 数据存储

数据存储于 `~/.our-family-ledger/data.db`（SQLite），兼容原 iOS 项目的 CSV 导出格式。

## 命令

### 记账 CRUD

```bash
# 添加交易
ledger add --amount 45 --type 支出 --category 餐饮 --payer 我 --participants 我,老婆

# 列出本月记录
ledger list

# 列出指定月份
ledger list --month 2026-05

# 按分类/成员筛选
ledger list --category 餐饮 --member 老婆

# 查看详情（输入ID前缀）
ledger show abc12345

# 修改
ledger edit abc12345 --amount 50

# 删除（有确认）
ledger delete abc12345
ledger delete abc12345 --force
```

### AI 自然语言记账

```bash
# 首次运行会引导配置 AI API
ledger chat

# 或先配置
ledger setup
ledger chat
```

### 统计报表

```bash
# 当月报表
ledger report

# 指定月份
ledger report --month 2026-05

# CSV 导出
ledger report --month 2026-05 --csv
```

### CSV 导入/导出

```bash
# 从原项目 CSV 导入
ledger import --file transactions.csv
ledger import --file "data/*.csv"

# 导出指定月份
ledger export --month 2026-05
ledger export --month 2026-05 --output 2026-05.csv
```

### 成员管理

```bash
# 列出成员
ledger members list

# 添加成员
ledger members add 老婆
ledger members add 小明
```

## 配置

AI 配置存储于 `~/.our-family-ledger/config.toml`：

```toml
[ai]
provider = "openai"
endpoint = "https://api.openai.com/v1"
model = "gpt-4o-mini"
api_key = "sk-..."
```
