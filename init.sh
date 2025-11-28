#!/bin/bash

# SatoriManager React Native 项目一键初始化脚本
# 使用方法: ./init.sh

set -e

echo "🚀 SatoriManager React Native 项目初始化..."
echo ""

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js 未安装，请先安装 Node.js 18+"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js 版本过低，需要 18+，当前: $(node -v)"
    exit 1
fi
echo "✅ Node.js: $(node -v)"

# 检查 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "📦 安装 pnpm..."
    npm install -g pnpm
fi
echo "✅ pnpm: $(pnpm -v)"

# 安装依赖
echo ""
echo "📦 安装项目依赖..."
pnpm install

# 检查 React Native CLI
if ! pnpm exec react-native --version &> /dev/null; then
    echo "📦 安装 React Native CLI..."
    pnpm add -D @react-native-community/cli
fi

# iOS 配置 (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo ""
    echo "🍎 配置 iOS..."

    if ! command -v pod &> /dev/null; then
        echo "📦 安装 CocoaPods..."
        sudo gem install cocoapods
    fi

    cd ios
    pod install
    cd ..
    echo "✅ iOS 配置完成"
fi

# Android 配置检查
echo ""
echo "🤖 检查 Android 配置..."

if [ -z "$ANDROID_HOME" ]; then
    echo "⚠️  ANDROID_HOME 环境变量未设置"
    echo "   请设置 Android SDK 路径:"
    echo "   export ANDROID_HOME=\$HOME/Android/Sdk  # Linux"
    echo "   export ANDROID_HOME=\$HOME/Library/Android/sdk  # macOS"
    echo "   或在 Windows 上设置系统环境变量"
else
    echo "✅ ANDROID_HOME: $ANDROID_HOME"
fi

echo ""
echo "=========================================="
echo "✅ 初始化完成!"
echo ""
echo "📱 启动开发服务器:"
echo "   pnpm start"
echo ""
echo "🤖 运行 Android:"
echo "   pnpm android"
echo ""
echo "🍎 运行 iOS (仅 macOS):"
echo "   pnpm ios"
echo "=========================================="
