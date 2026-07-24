#!/bin/bash
set -e

ORIGINAL_SCRIPT="build.sh"          # 原大脚本文件名，请根据实际情况修改
TMP_SCRIPT="build.sh.tmp"

echo "📦 从原脚本中释放文件并构建..."

# 备份原脚本，并插入退出逻辑
cp "$ORIGINAL_SCRIPT" "$TMP_SCRIPT"

# 在“构建并安装”之前插入条件退出（确保所有文件生成和配置修改都已执行）
sed -i '/# ==================== 构建并安装 ====================/i \
if [ "$EXTRACT_ONLY" = "true" ]; then \
    echo "✅ 文件已释放到项目目录，配置已修改，退出。" \
    exit 0 \
fi' "$TMP_SCRIPT"

# 设置环境变量，执行修改后的脚本（只做释放和配置，不构建）
EXTRACT_ONLY=true bash "$TMP_SCRIPT"

# 清理临时脚本
rm -f "$TMP_SCRIPT"

# 现在所有源文件、资源、配置都已就位，直接构建
echo "🔨 开始构建 APK..."
./gradlew clean assembleDebug

APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
    echo "📲 安装 APK（覆盖安装）..."
    adb install -r "$APK_PATH"
    echo "🎉 构建并安装完成！"
else
    echo "❌ 构建失败，未找到 APK"
    exit 1
fi
