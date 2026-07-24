#!/bin/bash

# 不设置 set -e，让脚本可以处理错误

ORIGINAL_SCRIPT="deploy_ku9.sh"
TMP_SCRIPT="deploy_ku9_tmp.sh"

echo "📦 正在从原脚本中释放所有文件..."

# 1. 复制原脚本为临时脚本
cp "$ORIGINAL_SCRIPT" "$TMP_SCRIPT"

# 2. 修改临时脚本：
#    - 将 set -e 改为 set +e，避免因某些命令失败而退出（如网络下载失败）
#    - 在 "构建并安装" 这一行之前插入 exit 0，使脚本在生成完文件后退出
sed -i 's/^set -e/set +e/' "$TMP_SCRIPT"
sed -i '/# ==================== 构建并安装 ====================/i\
    echo "✅ 文件已全部生成，退出。\
    exit 0' "$TMP_SCRIPT"

# 3. 执行临时脚本（这会创建所有源文件、资源、布局，并复制到 app/ 目录）
echo "⏳ 运行原脚本生成文件..."
bash "$TMP_SCRIPT"

# 4. 删除临时脚本
rm -f "$TMP_SCRIPT"

# 5. 检查关键文件是否已生成
if [ ! -f "app/src/main/java/com/whyun/witv/MainActivity.java" ]; then
    echo "❌ 文件释放失败，未找到 MainActivity.java"
    echo "请检查原脚本是否成功执行，或手动运行原脚本查看错误。"
    exit 1
fi

echo "✅ 所有文件已成功释放到 app/ 目录。"

# 6. 现在进行构建配置（签名、权限、横屏等）
# 注意：原脚本可能已经修改了 build.gradle 和 AndroidManifest，但因为我们提前退出，
# 这些修改可能未执行，所以需要在这里补做。

echo "⚙️ 正在应用签名和配置修改..."

# 6.1 生成 keystore（如果不存在）
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

# 6.2 修改 app/build.gradle 添加签名配置
APP_GRADLE="app/build.gradle"
if ! grep -q "signingConfigs" "$APP_GRADLE"; then
    sed -i '/android {/a \    signingConfigs {\n        release {\n            storeFile file("'"$KEYSTORE_FILE"'")\n            storePassword "'"$KEYSTORE_PASS"'"\n            keyAlias "'"$KEY_ALIAS"'"\n            keyPassword "'"$KEY_PASS"'"\n        }\n    }' "$APP_GRADLE"
fi
# 让 debug 和 release 使用该签名
sed -i '/buildTypes {/a \        debug {\n            signingConfig signingConfigs.release\n        }\n        release {\n            signingConfig signingConfigs.release\n        }' "$APP_GRADLE"

# 6.3 修改 AndroidManifest.xml（横屏、权限、cleartext）
MANIFEST="app/src/main/AndroidManifest.xml"
# 提取原脚本中的 python 代码（用于设置横屏和图标）并执行
python_code=$(sed -n '/cat > \/tmp\/fix_manifest.py/,/EOF/p' "$ORIGINAL_SCRIPT" | sed '1d;$d')
if [ -n "$python_code" ]; then
    echo "$python_code" | python3
fi
# 补充权限和 cleartext（如果 python 脚本未完全覆盖）
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"

# 6.4 添加依赖（如果尚未添加）
if ! grep -q "media3-exoplayer" "$APP_GRADLE"; then
    sed -i '/dependencies {/a \    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
fi

# 6.5 处理自定义图标
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

# 7. 开始构建
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
