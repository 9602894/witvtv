#!/bin/bash
set -e

ORIGINAL_SCRIPT="build.sh"    # 原大脚本
TMP_SCRIPT="build.sh.extract"

echo "📦 从原脚本提取文件到项目目录（跳过构建）..."

# 复制原脚本
cp "$ORIGINAL_SCRIPT" "$TMP_SCRIPT"

# 注释掉所有包含 gradlew 或 adb install 的行（以及可能存在的构建相关 echo）
sed -i 's/^\(.*\.\/gradlew.*\)/#\1/' "$TMP_SCRIPT"
sed -i 's/^\(.*adb install.*\)/#\1/' "$TMP_SCRIPT"
# 也可能有 “构建并安装” 的 echo，可选择性注释
sed -i 's/^\(.*构建并安装.*\)/#\1/' "$TMP_SCRIPT"
sed -i 's/^\(.*APK_PATH.*\)/#\1/' "$TMP_SCRIPT"
# 可能还有 if [ -f "$APK_PATH" ] 等，一并注释
sed -i 's/^\([[:space:]]*if \[ -f "\$APK_PATH" \].*\)/#\1/' "$TMP_SCRIPT"
sed -i 's/^\([[:space:]]*adb.*\)/#\1/' "$TMP_SCRIPT"
sed -i 's/^\([[:space:]]*echo.*安装完成.*\)/#\1/' "$TMP_SCRIPT"

# 执行修改后的脚本，此时所有 cat 和 cp 都会执行，但构建跳过
bash "$TMP_SCRIPT"

# 清理
rm -f "$TMP_SCRIPT"

echo "✅ 文件释放完成！现在可以手动执行 ./gradlew assembleDebug 构建"
