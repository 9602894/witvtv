#!/bin/bash
set -e

ORIGINAL_SCRIPT="deploy_ku9.sh"   # 用户的大脚本文件名

echo "📦 从原脚本中释放文件并构建..."

# 备份原脚本
cp "$ORIGINAL_SCRIPT" "$ORIGINAL_SCRIPT.bak"

# 修改原脚本：在“构建并安装”之前插入 exit
# 查找“构建并安装”的注释行，在其前插入 exit
sed -i '/# ==================== 构建并安装 ====================/i \
    echo "✅ 文件已释放到项目目录，配置已修改，退出。" \
    exit 0' "$ORIGINAL_SCRIPT"

# 运行修改后的脚本，生成文件
bash "$ORIGINAL_SCRIPT"

# 恢复原脚本
mv "$ORIGINAL_SCRIPT.bak" "$ORIGINAL_SCRIPT"

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
