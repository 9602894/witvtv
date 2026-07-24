#!/bin/bash
set -e

ORIGINAL_SCRIPT="deploy_ku9.sh"   # 原大脚本的文件名

echo "📦 正在从原脚本中提取所有文件..."

# ---------- 1. 提取所有 heredoc 文件 ----------
# 使用 awk 解析原脚本，识别 cat > "路径" <<'EOF' ... EOF 块
awk '
BEGIN {
    root = "."
    outfile = ""
    in_heredoc = 0
}
/^cat > / {
    # 匹配 cat > "path" 或 cat > path
    if (match($0, /cat >[[:space:]]*["'\'']?([^"'\''[:space:]]+)/, arr)) {
        outfile = arr[1]
        # 去掉可能的 "./" 前缀
        if (outfile ~ /^\.\//) {
            outfile = substr(outfile, 3)
        }
        # 创建目录
        system("mkdir -p $(dirname " outfile ")")
        in_heredoc = 1
        next
    }
}
in_heredoc && /^<<'\''EOF'\''/ {
    in_heredoc = 2   # 开始读取内容
    next
}
in_heredoc == 2 {
    if ($0 == "EOF") {
        in_heredoc = 0
        outfile = ""
        next
    }
    # 写入文件
    print >> outfile
}
' "$ORIGINAL_SCRIPT"

echo "✅ 所有源文件、布局、资源已提取。"

# ---------- 2. 执行配置修改（签名、横屏、权限等） ----------
# 这些修改在原脚本中是通过 sed 和 python 内联实现的，我们直接复用这些命令。

echo "⚙️ 正在应用配置修改..."

# 2.1 修改 build.gradle 添加签名（如果尚未添加）
APP_GRADLE="app/build.gradle"
KEYSTORE_FILE="$PROJECT_DIR/keystore.jks"
KEYSTORE_PASS="witv123"
KEY_ALIAS="witv"
KEY_PASS="witv123"

# 生成 keystore（如果不存在）
if [ ! -f "$KEYSTORE_FILE" ]; then
    echo "🔑 生成 keystore..."
    keytool -genkey -v -keystore "$KEYSTORE_FILE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass "$KEYSTORE_PASS" -keypass "$KEY_PASS" \
        -dname "CN=Witv, OU=Dev, O=Witv, L=City, S=State, C=CN"
fi

# 添加 signingConfigs（如果不存在）
if ! grep -q "signingConfigs" "$APP_GRADLE"; then
    sed -i '/android {/a \    signingConfigs {\n        release {\n            storeFile file("'"$KEYSTORE_FILE"'")\n            storePassword "'"$KEYSTORE_PASS"'"\n            keyAlias "'"$KEY_ALIAS"'"\n            keyPassword "'"$KEY_PASS"'"\n        }\n    }' "$APP_GRADLE"
fi
# 让 debug 和 release 使用该签名
sed -i '/buildTypes {/a \        debug {\n            signingConfig signingConfigs.release\n        }\n        release {\n            signingConfig signingConfigs.release\n        }' "$APP_GRADLE"

# 2.2 修改 AndroidManifest.xml（横屏、权限、cleartext）
MANIFEST="app/src/main/AndroidManifest.xml"
# 提取原脚本中的 python 脚本（用于修改 manifest）
python3 -c "$(sed -n '/cat > \/tmp\/fix_manifest.py/,/EOF/p' "$ORIGINAL_SCRIPT" | sed '1d;$d')"
# 添加权限和 cleartext（如果原脚本的 python 未覆盖）
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"

# 2.3 复制 assets 文件（如果原脚本已生成，但可能未复制）
# 原脚本会复制 configuration.json 和 epg_data.json 到 assets，我们手动确保
mkdir -p app/src/main/assets
if [ -f "$TEMPLATE_DIR/configuration.json" ]; then
    cp "$TEMPLATE_DIR/configuration.json" app/src/main/assets/
fi
if [ -f "$TEMPLATE_DIR/assets/epg_data.json" ]; then
    cp "$TEMPLATE_DIR/assets/epg_data.json" app/src/main/assets/
fi

# 2.4 自定义图标（如果存在）
if [ -f "apk ico.jpeg" ]; then
    cp "apk ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk_ico.jpeg" ]; then
    cp "apk_ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk ico.png" ]; then
    cp "apk ico.png" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
fi

echo "✅ 配置修改完成。"

# ---------- 3. 构建并安装 ----------
echo "🔨 开始构建 APK..."
./gradlew clean assembleDebug

APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
    if command -v adb &> /dev/null; then
        echo "📲 安装 APK（覆盖安装）..."
        adb install -r "$APK_PATH"
        echo "🎉 构建并安装完成！"
    else
        echo "⚠️ adb 未找到，跳过安装。APK 位于: $APK_PATH"
    fi
else
    echo "❌ 构建失败，未找到 APK"
    exit 1
fi
