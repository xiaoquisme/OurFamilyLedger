#!/bin/bash

# OurFamilyLedger 项目设置脚本

set -e

echo "=== OurFamilyLedger 项目设置 ==="
echo ""

# 检查是否安装了 xcodegen
if command -v xcodegen &> /dev/null; then
    echo "检测到 xcodegen，正在生成 Xcode 项目..."
    xcodegen generate
    echo "项目生成成功！"
    echo ""
    echo "使用以下命令打开项目："
    echo "  open OurFamilyLedger.xcodeproj"
else
    echo "未检测到 xcodegen。"
    echo ""
    echo "你可以选择："
    echo ""
    echo "1. 安装 xcodegen 并生成项目："
    echo "   brew install xcodegen"
    echo "   xcodegen generate"
    echo ""
    echo "2. 手动创建 Xcode 项目："
    echo "   a. 打开 Xcode"
    echo "   b. 选择 File > New > Project"
    echo "   c. 选择 iOS > App"
    echo "   d. 产品名称: OurFamilyLedger"
    echo "   e. 选择 SwiftUI 和 Swift"
    echo "   f. 将生成的源代码文件复制到项目中"
    echo ""
    echo "3. 使用 Swift Package Manager (如果你只需要核心逻辑)："
    echo "   swift build"
fi

echo ""
echo "项目文件结构："
find OurFamilyLedger -name "*.swift" | head -20

echo ""
echo "=== 设置完成 ==="
