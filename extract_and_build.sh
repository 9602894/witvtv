#!/bin/bash
set -e
ORIGINAL_SCRIPT="deploy_ku9.sh"
echo "📦 从原脚本中提取文件并写入最终位置..."

# 定义路径映射函数
map_path() {
    local path="$1"
    # 去掉可能的引号
    path=${path#\"}
    path=${path%\"}
    # 替换 $TEMPLATE_DIR
    # 注意：原脚本中 TEMPLATE_DIR 被设置为 "./config"
    # 我们将 "./config/src/" 映射为 "app/src/main/java/com/whyun/witv/"
    # 将 "./config/res/" 映射为 "app/src/main/res/"
    # 将 "./config/assets/" 映射为 "app/src/main/assets/"
    # 将 "./config/configuration.json" 映射为 "app/src/main/assets/configuration.json"
    # 将 "./config/" 下其他文件映射到 app/src/main/assets/?
    # 实际上只有几个特定文件，我们可以单独处理
    case "$path" in
        ./config/src/*)
            # 替换 ./config/src/ 为 app/src/main/java/com/whyun/witv/
            echo "${path/.\/config\/src\//app/src/main/java/com/whyun/witv/}"
            ;;
        ./config/res/*)
            echo "${path/.\/config\/res\//app/src/main/res/}"
            ;;
        ./config/assets/*)
            echo "${path/.\/config\/assets\//app/src/main/assets/}"
            ;;
        ./config/configuration.json)
            echo "app/src/main/assets/configuration.json"
            ;;
        ./config/*)
            # 其他config下的文件，放到assets? 但原脚本只有configuration.json和epg_data.json，epg_data.json在assets下，但原脚本中它被cat到 $TEMPLATE_DIR/assets/epg_data.json，所以走上面映射
            # 这里备用
            echo "app/src/main/assets/$(basename "$path")"
            ;;
        *)
            echo "$path"
            ;;
    esac
}

# 状态变量
in_heredoc=0
outfile=""
line_num=0

# 读取原脚本，逐行处理
while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_num++))
    # 检查是否是 cat > 行
    if [[ $in_heredoc -eq 0 && "$line" =~ ^[[:space:]]*cat[[:space:]]+> ]]; then
        # 提取目标路径
        # 匹配 cat > "路径" 或 cat > 路径
        if [[ "$line" =~ cat[[:space:]]+>[[:space:]]*\"([^\"]+)\" ]]; then
            raw_path="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ cat[[:space:]]+>[[:space:]]*([^[:space:]]+) ]]; then
            raw_path="${BASH_REMATCH[1]}"
        else
            continue
        fi
        # 映射路径
        outfile=$(map_path "$raw_path")
        # 创建目录
        mkdir -p "$(dirname "$outfile")"
        in_heredoc=1
        # 清空文件（如果存在）
        > "$outfile"
        echo "📄 开始提取: $outfile"
        continue
    fi

    if [[ $in_heredoc -eq 1 ]]; then
        # 检查是否遇到结束标志 <<'EOF' 或 <<EOF
        if [[ "$line" =~ ^[[:space:]]*<<[[:space:]]*\'?EOF\'?[[:space:]]*$ ]]; then
            in_heredoc=2
            continue
        fi
    fi

    if [[ $in_heredoc -eq 2 ]]; then
        if [[ "$line" == "EOF" ]]; then
            in_heredoc=0
            outfile=""
            echo "✅ 完成提取"
            continue
        fi
        # 写入内容
        echo "$line" >> "$outfile"
    fi
done < "$ORIGINAL_SCRIPT"

echo "✅ 所有文件提取完成。"

# 接下来执行原脚本中的配置修改命令（签名、manifest等）
# 我们直接从原脚本中复制相关命令，或者直接调用原脚本中的相应片段。
# 但为了简单，我们直接手动执行这些命令（因为原脚本中的这些命令是独立的）。

echo "⚙️ 应用配置修改..."

# 生成 keystore（如果需要）
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

# 修改 build.gradle
APP_GRADLE="app/build.gradle"
if ! grep -q "signingConfigs" "$APP_GRADLE"; then
    sed -i '/android {/a \    signingConfigs {\n        release {\n            storeFile file("'"$KEYSTORE_FILE"'")\n            storePassword "'"$KEYSTORE_PASS"'"\n            keyAlias "'"$KEY_ALIAS"'"\n            keyPassword "'"$KEY_PASS"'"\n        }\n    }' "$APP_GRADLE"
fi
sed -i '/buildTypes {/a \        debug {\n            signingConfig signingConfigs.release\n        }\n        release {\n            signingConfig signingConfigs.release\n        }' "$APP_GRADLE"

# 修改 AndroidManifest.xml
MANIFEST="app/src/main/AndroidManifest.xml"
# 添加权限和 cleartext
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"

# 设置横屏和图标（原脚本中有python脚本，我们可以提取并执行）
# 更简单：直接手动修改 manifest 中的 activity 属性
# 但是原脚本中会删除所有 activity 并重新创建，我们用 python 脚本执行一下。
# 从原脚本提取 python 代码并执行
python_code=$(sed -n '/cat > \/tmp\/fix_manifest.py/,/EOF/p' "$ORIGINAL_SCRIPT" | sed '1d;$d')
if [ -n "$python_code" ]; then
    echo "$python_code" | python3
fi

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

# 添加依赖（原脚本中也有，但可能已经存在于 build.gradle，我们确保一下）
# 如果未添加，则添加
if ! grep -q "media3-exoplayer" "$APP_GRADLE"; then
    sed -i '/dependencies {/a \    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
fi

echo "✅ 配置修改完成。"

# 构建并安装
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
