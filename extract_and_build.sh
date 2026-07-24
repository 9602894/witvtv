#!/bin/bash
set -e

ORIGINAL_SCRIPT="deploy_ku9.sh"   # 原大脚本的文件名

echo "📦 正在从原脚本中提取所有文件..."

# ---------- 1. 提取所有 heredoc 文件 ----------
# 使用 awk 解析原脚本，识别 cat > "路径" <<'EOF' ... EOF 块
# 同时将路径中的 ./config/ 替换为 app/src/main/ 等最终路径
awk '
BEGIN {
    # 定义路径映射函数
    function map_path(path) {
        # 去掉可能的引号
        gsub(/^"/, "", path)
        gsub(/"$/, "", path)
        # 替换 ./config/src/ -> app/src/main/java/com/whyun/witv/
        if (path ~ /^\.\/config\/src\//) {
            sub(/^\.\/config\/src\//, "app/src/main/java/com/whyun/witv/", path)
        }
        # 替换 ./config/res/ -> app/src/main/res/
        else if (path ~ /^\.\/config\/res\//) {
            sub(/^\.\/config\/res\//, "app/src/main/res/", path)
        }
        # 替换 ./config/assets/ -> app/src/main/assets/
        else if (path ~ /^\.\/config\/assets\//) {
            sub(/^\.\/config\/assets\//, "app/src/main/assets/", path)
        }
        # 替换 ./config/configuration.json -> app/src/main/assets/configuration.json
        else if (path == "./config/configuration.json") {
            path = "app/src/main/assets/configuration.json"
        }
        # 其他 ./config/ 下的文件放到 assets（备用）
        else if (path ~ /^\.\/config\//) {
            sub(/^\.\/config\//, "app/src/main/assets/", path)
        }
        return path
    }

    outfile = ""
    in_heredoc = 0
}
/^cat > / {
    # 匹配 cat > "路径" 或 cat > 路径
    if (match($0, /cat >[[:space:]]*["'\'']?([^"'\''[:space:]]+)/, arr)) {
        raw_path = arr[1]
        outfile = map_path(raw_path)
        # 创建目录
        system("mkdir -p $(dirname " outfile ")")
        # 清空文件（如果存在）
        system("> " outfile)
        print "📄 提取: " outfile
        in_heredoc = 1
        next
    }
}
in_heredoc && /^<<'\''EOF'\''/ {
    in_heredoc = 2
    next
}
in_heredoc == 2 {
    if ($0 == "EOF") {
        in_heredoc = 0
        outfile = ""
        next
    }
    # 写入内容
    print >> outfile
}
' "$ORIGINAL_SCRIPT"

echo "✅ 所有文件提取完成。"

# ---------- 2. 执行配置修改（签名、横屏、权限等） ----------
# 这些命令从原脚本中提取，手动执行

echo "⚙️ 正在应用配置修改..."

# 生成 keystore（如果不存在）
KEYSTORE_FILE="./keystore.jks"
KEYSTORE_PASS="witv123"
KEY_ALIAS="witv"
KEY_PASS="witv123"
if [ ! -f "$KEYSTORE_FILE" ]; then
    echo "🔑 生成 keystore..."
    keytool -genkey -v -keystore "$KEYSTORE_FILE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass "$KEYSTORE_PASS" -keypass "$KEY_PASS" \
        -dname "CN=Witv, OU=Dev, O=Witv, L=City, S=State, C=CN"
fi

# 修改 app/build.gradle 添加签名配置
APP_GRADLE="app/build.gradle"
if ! grep -q "signingConfigs" "$APP_GRADLE"; then
    sed -i '/android {/a \    signingConfigs {\n        release {\n            storeFile file("'"$KEYSTORE_FILE"'")\n            storePassword "'"$KEYSTORE_PASS"'"\n            keyAlias "'"$KEY_ALIAS"'"\n            keyPassword "'"$KEY_PASS"'"\n        }\n    }' "$APP_GRADLE"
fi
# 让 debug 和 release 使用该签名
sed -i '/buildTypes {/a \        debug {\n            signingConfig signingConfigs.release\n        }\n        release {\n            signingConfig signingConfigs.release\n        }' "$APP_GRADLE"

# 修改 AndroidManifest.xml（横屏、权限、cleartext）
MANIFEST="app/src/main/AndroidManifest.xml"
# 提取原脚本中的 python 脚本并执行（用于设置横屏和图标）
python_code=$(sed -n '/cat > \/tmp\/fix_manifest.py/,/EOF/p' "$ORIGINAL_SCRIPT" | sed '1d;$d')
if [ -n "$python_code" ]; then
    echo "$python_code" | python3
fi
# 添加权限和 cleartext（如果 python 脚本未覆盖）
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"

# 处理自定义图标（如果有）
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

# 添加依赖（如果尚未添加）
if ! grep -q "media3-exoplayer" "$APP_GRADLE"; then
    sed -i '/dependencies {/a \    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
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
