#!/bin/bash
set -e
echo "🔥 部署 witv 播放器（酷9风格弹窗 + 固定签名 + 横屏 + 网速显示）- 完整版"
PROJECT_DIR="$(pwd)"
TEMPLATE_DIR="./config"
rm -rf "$TEMPLATE_DIR"
mkdir -p "$TEMPLATE_DIR"/{src,res/layout,res/drawable,res/values,assets}
mkdir -p "$TEMPLATE_DIR/src/epg" "$TEMPLATE_DIR/src/player" "$TEMPLATE_DIR/src/favorite" "$TEMPLATE_DIR/src/utils"

# ==================== 生成固定签名 keystore ====================
KEYSTORE_FILE="$PROJECT_DIR/keystore.jks"
KEYSTORE_PASS="witv123"
KEY_ALIAS="witv"
KEY_PASS="witv123"
if [ ! -f "$KEYSTORE_FILE" ]; then
    echo "🔑 生成 keystore（用于固定签名）..."
    keytool -genkey -v -keystore "$KEYSTORE_FILE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass "$KEYSTORE_PASS" -keypass "$KEY_PASS" \
        -dname "CN=Witv, OU=Dev, O=Witv, L=City, S=State, C=CN"
    echo "✅ keystore 生成完成: $KEYSTORE_FILE"
else
    echo "✅ 已存在 keystore: $KEYSTORE_FILE"
fi

# ==================== 下载 epg_data.json ====================
echo "📥 下载别名映射 epg_data.json ..."
curl -s -L -o "$TEMPLATE_DIR/assets/epg_data.json" "https://raw.githubusercontent.com/tytestelle/witv/main/assets/epg_data.json" || \
wget -q -O "$TEMPLATE_DIR/assets/epg_data.json" "https://raw.githubusercontent.com/tytestelle/witv/main/assets/epg_data.json"
if [ ! -f "$TEMPLATE_DIR/assets/epg_data.json" ]; then
    echo '{"epgs":[]}' > "$TEMPLATE_DIR/assets/epg_data.json"
fi

# ==================== configuration.json ====================
cat > "$TEMPLATE_DIR/configuration.json" <<'EOF'
{"Configuration":{"LIVE_URLS":null,"EPG_URLS":"https://raw.githubusercontent.com/9602894/sandiJMYG/main/epg_data/epg_merged.xml","PLAY_TYPE":7,"PLAY_SCALE":3,"LIVE_CONNECT_TIMEOUT":30,"LIVE_SHOW_TIME":false,"LIVE_SHOW_NET_SPEED":false,"HIDE_Channel_LOGO":true,"HIDE_Bottom_LOGO":true,"CLOSE_EPG":false,"HIDE_FAVOR":false,"HIDE_NUMBER":false,"PL_MEMORYS_ET_SELECT":false,"LIVE_CHANNEL_REVERSE":false,"LIVE_CROSS_GROUP":false,"LIVE_SKIP_PASSWORD":false,"PIC_IN_PIC":false,"BOOT_START":false,"QUICK_EXIT":false,"EYE_PROTECTION":false,"PLAYBACK_ID":false,"TIME_SHIFT_ON":true,"PLAY_RENDER":1,"DOH_URL":0,"THEME_SELECT":2,"PLAY_BACK_TYPE":0,"RECONNECT_INDEX":0,"EXO_TUNNELING_SELECT":false,"RTSP_TCP_SELECT":0,"NAVIGATION_SELECT":0,"EPG_SHOW_TYPE_SELECT":0,"TEXT_SIZE":0,"LIST_WIDTH":0,"BOTTOM_WIDTH":0,"EPGCACHE_SELECT":4,"IMAGECACHE_SELECT":false,"SCRIPT_CACHE":true,"MEMORYS_SOURCE":true,"MEMORYS_POSITION":true,"BACKGROUND_THEME_SELECT":6,"BOOTRECEIVER_SET_SELECT":true,"SHORTCUTS_MENU":false,"SHORTCUTS_MENU_SELECT":"列表订阅,EPG订阅,无线投屏,频道搜索,APP信息","GROUP_PARS_SET_SELECT":3,"PLAY_ALL_SOURCE":true,"RESOLUTION_MODE_SELECT":0,"TIME_ZONE_SELECT":0,"TIME_SHIFT_MODE":0,"ENABLE_LOCAL_VIDEO":false,"M3U_LOGO_PRIORITY":false,"EPG_DESC_SET":false,"BOTTOM_DESC_SET":true,"ICON_INITIAL_SET":true,"EPG_CACHE_PATH_SET":false,"AUDIO_WAKKPAPER":false,"DE_INTERLACING":false}}
EOF

# ==================== 生成所有 Java 源文件（完整无缺） ====================
# ---------- SourceManager.java ----------
cat > "$TEMPLATE_DIR/src/SourceManager.java" <<'SRCMGR'
package com.whyun.witv.source;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class SourceManager {
    private Context context;
    private Map<String, List<Channel>> groupMap = new HashMap<>();
    private List<String> groupNames = new ArrayList<>();
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    public interface OnSourceLoadListener { void onLoaded(Map<String, List<Channel>> groupMap, List<String> groupNames); void onError(String error); }
    public SourceManager(Context context) { this.context = context; }
    public void loadFromUrl(String url, OnSourceLoadListener listener) {
        new Thread(() -> {
            try {
                OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                    .build();
                Request request = new Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .build();
                Response response = client.newCall(request).execute();
                if (response.code() != 200) throw new Exception("HTTP " + response.code());
                String content = response.body().string();
                if (content == null || content.trim().isEmpty()) throw new Exception("内容为空");
                if (url.endsWith(".m3u") || url.endsWith(".m3u8") || content.contains("#EXTM3U")) {
                    parseM3U(content);
                } else {
                    parseTXT(content);
                }
                if (groupMap.isEmpty()) throw new Exception("未解析到任何频道");
                mainHandler.post(() -> listener.onLoaded(groupMap, groupNames));
            } catch (Exception e) {
                mainHandler.post(() -> listener.onError(e.getMessage()));
            }
        }).start();
    }
    private void parseTXT(String content) {
        groupMap.clear(); groupNames.clear();
        String currentGroup = "默认分组";
        for (String line : content.split("\n")) {
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.endsWith("#genre#")) {
                String groupName = line.substring(0, line.length() - "#genre#".length()).trim();
                if (groupName.endsWith(",")) groupName = groupName.substring(0, groupName.length()-1).trim();
                if (!groupName.isEmpty()) {
                    currentGroup = groupName;
                    if (!groupMap.containsKey(currentGroup)) {
                        groupMap.put(currentGroup, new ArrayList<>());
                        groupNames.add(currentGroup);
                    }
                }
                continue;
            }
            if (line.startsWith("#")) continue;
            String[] parts = line.split(",");
            if (parts.length >= 2) {
                String name = parts[0].trim();
                if (name.endsWith(",")) name = name.substring(0, name.length()-1).trim();
                String url = parts[1].trim();
                if (name.isEmpty() || url.isEmpty()) continue;
                Channel ch = new Channel(name, url, currentGroup);
                if (!groupMap.containsKey(currentGroup)) {
                    groupMap.put(currentGroup, new ArrayList<>());
                    groupNames.add(currentGroup);
                }
                groupMap.get(currentGroup).add(ch);
            }
        }
    }
    private void parseM3U(String content) {
        groupMap.clear(); groupNames.clear();
        String[] lines = content.split("\n");
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.startsWith("#EXTM3U")) continue;
            if (line.startsWith("#EXTINF:")) {
                String group = "默认分组";
                String logo = null;
                int gidx = line.indexOf("group-title=\"");
                if (gidx != -1) {
                    int end = line.indexOf("\"", gidx + 13);
                    if (end != -1) group = line.substring(gidx + 13, end);
                }
                int lidx = line.indexOf("tvg-logo=\"");
                if (lidx != -1) {
                    int end = line.indexOf("\"", lidx + 10);
                    if (end != -1) logo = line.substring(lidx + 10, end);
                }
                int lastComma = line.lastIndexOf(",");
                String name = (lastComma != -1) ? line.substring(lastComma + 1).trim() : "未知频道";
                if (name.endsWith(",")) name = name.substring(0, name.length()-1).trim();
                if (i + 1 < lines.length) {
                    String url = lines[i + 1].trim();
                    if (!url.isEmpty() && !url.startsWith("#")) {
                        Channel ch = new Channel(name, url, group);
                        ch.logoUrl = logo;
                        if (!groupMap.containsKey(group)) {
                            groupMap.put(group, new ArrayList<>());
                            groupNames.add(group);
                        }
                        groupMap.get(group).add(ch);
                    }
                }
            }
        }
    }
    public static class Channel {
        public String name, url, group;
        public String logoUrl;
        public Channel(String n, String u, String g) { name=n; url=u; group=g; }
    }
}
SRCMGR

# ---------- LogUtils.java ----------
cat > "$TEMPLATE_DIR/src/utils/LogUtils.java" <<'LOGUTIL'
package com.whyun.witv.utils;
import android.content.Context;
import android.os.Environment;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
public class LogUtils {
    private static final String APP_DIR = "witv";
    private static final String LOG_DIR_NAME = "logs";
    private static final String LOG_FILE = "app.log";
    private static String sLogDirPath = null;
    private static String sAppRoot = null;
    public static void init(Context context) {
        if (sLogDirPath != null) return;
        File baseDir = null;
        try {
            if (Environment.getExternalStorageState().equals(Environment.MEDIA_MOUNTED)) {
                File extDir = new File(Environment.getExternalStorageDirectory(), APP_DIR);
                if (extDir.exists() || extDir.mkdirs()) baseDir = extDir;
            }
        } catch (Exception e) { Log.e("LogUtils", "外部存储不可用", e); }
        if (baseDir == null) {
            File internalDir = new File(context.getFilesDir(), APP_DIR);
            if (internalDir.exists() || internalDir.mkdirs()) baseDir = internalDir;
        }
        if (baseDir == null) { baseDir = new File(context.getCacheDir(), APP_DIR); baseDir.mkdirs(); }
        createAppDirectories(baseDir);
        File logDir = new File(baseDir, LOG_DIR_NAME);
        if (!logDir.exists()) logDir.mkdirs();
        sLogDirPath = logDir.getAbsolutePath();
        sAppRoot = baseDir.getAbsolutePath();
        writeLog("=== 日志系统初始化成功，根目录: " + sAppRoot + "，日志目录: " + sLogDirPath + " ===");
    }
    public static String getLogDir() { return sLogDirPath != null ? sLogDirPath : ""; }
    public static String getAppRootDir() { return sAppRoot != null ? sAppRoot : ""; }
    public static String getEpgCacheDir() { String root = getAppRootDir(); return root.isEmpty() ? "" : root + "/epgCache"; }
    public static String getEpgHashFile() { String root = getAppRootDir(); return root.isEmpty() ? "" : root + "/epg_hash.txt"; }
    public static String getConfigDir() { String root = getAppRootDir(); return root.isEmpty() ? "" : root + "/configuration"; }
    public static String getLogoDir() { String root = getAppRootDir(); return root.isEmpty() ? "" : root + "/logo"; }
    public static void writeLog(String message) { if (sLogDirPath == null) return; try { String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date()); String log = time + " - " + message + "\n"; File logFile = new File(sLogDirPath, LOG_FILE); File parent = logFile.getParentFile(); if (parent != null && !parent.exists()) parent.mkdirs(); FileOutputStream fos = new FileOutputStream(logFile, true); fos.write(log.getBytes()); fos.close(); } catch (Exception e) { Log.e("LogUtils", "写入日志失败", e); } }
    public static void writeCrashLog(Throwable t) { if (sLogDirPath == null) return; try { String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date()); StringWriter sw = new StringWriter(); PrintWriter pw = new PrintWriter(sw); t.printStackTrace(pw); String stack = sw.toString(); String log = "========== CRASH at " + time + " ==========\n" + stack + "\n\n"; String fileName = "crash_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(new Date()) + ".txt"; File logFile = new File(sLogDirPath, fileName); File parent = logFile.getParentFile(); if (parent != null && !parent.exists()) parent.mkdirs(); FileOutputStream fos = new FileOutputStream(logFile); fos.write(log.getBytes()); fos.close(); writeLog("CRASH: " + t.getMessage()); } catch (Exception e) { Log.e("LogUtils", "写入崩溃日志失败", e); } }
    public static void createAppDirectories(File baseDir) { if (baseDir == null) return; String[] subDirs = {"localData", "backup", "download", "videoFile", "configuration", "logo", "js", "py", "webviewJscode", "epgCache", "logs"}; for (String sub : subDirs) { File dir = new File(baseDir, sub); if (!dir.exists()) dir.mkdirs(); } writeLog("应用目录创建完成: " + baseDir.getAbsolutePath()); }
}
LOGUTIL

# ---------- ConfigurationManager.java ----------
mkdir -p "$TEMPLATE_DIR/src"
cat > "$TEMPLATE_DIR/src/ConfigurationManager.java" <<'CONFIG'
package com.whyun.witv;
import android.content.Context;
import android.content.res.AssetManager;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import com.whyun.witv.utils.LogUtils;
public class ConfigurationManager {
    private static ConfigurationManager instance;
    private JSONObject config;
    private ConfigurationManager(Context context) { loadConfig(context); }
    public static synchronized ConfigurationManager getInstance(Context context) {
        if (instance == null) instance = new ConfigurationManager(context);
        return instance;
    }
    private void loadConfig(Context context) {
        try {
            String json = null;
            String configDir = LogUtils.getConfigDir();
            if (!configDir.isEmpty()) {
                File extFile = new File(configDir, "configuration.json");
                if (extFile.exists()) {
                    FileInputStream fis = new FileInputStream(extFile);
                    byte[] buffer = new byte[(int) extFile.length()];
                    fis.read(buffer);
                    fis.close();
                    json = new String(buffer, StandardCharsets.UTF_8);
                    LogUtils.writeLog("从外部存储加载配置: " + extFile.getAbsolutePath());
                }
            }
            if (json == null) {
                AssetManager am = context.getAssets();
                InputStream is = am.open("configuration.json");
                byte[] buffer = new byte[is.available()];
                is.read(buffer);
                is.close();
                json = new String(buffer, StandardCharsets.UTF_8);
                LogUtils.writeLog("从 assets 加载配置");
            }
            JSONObject root = new JSONObject(json);
            config = root.getJSONObject("Configuration");
        } catch (Exception e) {
            LogUtils.writeLog("加载配置失败: " + e.getMessage());
            config = new JSONObject();
        }
    }
    public String getString(String key, String defaultValue) { return config != null ? config.optString(key, defaultValue) : defaultValue; }
    public boolean getBoolean(String key, boolean defaultValue) { return config != null ? config.optBoolean(key, defaultValue) : defaultValue; }
    public int getInt(String key, int defaultValue) { return config != null ? config.optInt(key, defaultValue) : defaultValue; }
}
CONFIG

# ---------- PlayerConfigManager.java ----------
mkdir -p "$TEMPLATE_DIR/src/player"
cat > "$TEMPLATE_DIR/src/player/PlayerConfigManager.java" <<'PLAYER'
package com.whyun.witv.player;
import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
public class PlayerConfigManager {
    private static final String KEY_DECODER = "decoder_index";
    private static final String KEY_ASPECT = "aspect_ratio";
    private static SharedPreferences prefs;
    public static void init(Context context) { if (prefs == null) prefs = PreferenceManager.getDefaultSharedPreferences(context); }
    public static int getDecoder() { return prefs != null ? prefs.getInt(KEY_DECODER, 0) : 0; }
    public static void setDecoder(int index) { if (prefs != null) prefs.edit().putInt(KEY_DECODER, index).apply(); }
    public static String getAspectRatio() { return prefs != null ? prefs.getString(KEY_ASPECT, "默认") : "默认"; }
    public static void setAspectRatio(String aspect) { if (prefs != null) prefs.edit().putString(KEY_ASPECT, aspect).apply(); }
}
PLAYER

# ---------- FavoriteManager.java ----------
mkdir -p "$TEMPLATE_DIR/src/favorite"
cat > "$TEMPLATE_DIR/src/favorite/FavoriteManager.java" <<'FAV'
package com.whyun.witv.favorite;
import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import java.util.HashSet;
import java.util.Set;
public class FavoriteManager {
    private static final String KEY_FAVORITES = "favorites";
    private static SharedPreferences prefs;
    public static void init(Context context) { if (prefs == null) prefs = PreferenceManager.getDefaultSharedPreferences(context); }
    public static Set<String> getFavorites() { if (prefs == null) return new HashSet<>(); return new HashSet<>(prefs.getStringSet(KEY_FAVORITES, new HashSet<>())); }
    public static void setFavorites(Set<String> favorites) { if (prefs != null) prefs.edit().putStringSet(KEY_FAVORITES, favorites).apply(); }
    public static void addFavorite(String channelName) { if (prefs != null) { Set<String> set = getFavorites(); set.add(channelName); setFavorites(set); } }
    public static void removeFavorite(String channelName) { if (prefs != null) { Set<String> set = getFavorites(); set.remove(channelName); setFavorites(set); } }
    public static boolean isFavorite(String channelName) { return getFavorites().contains(channelName); }
}
FAV

# ---------- EPGParser.java ----------
cat > "$TEMPLATE_DIR/src/epg/EPGParser.java" <<'EPG'
package com.whyun.witv.epg;
import android.content.Context;
import android.util.Xml;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserException;
import org.json.JSONObject;
import org.json.JSONArray;
import com.whyun.witv.utils.LogUtils;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLDecoder;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class EPGParser {
    public interface OnEpgLoadListener { void onLoaded(List<EpgProgram> programs); void onError(String error); }
    public interface OnAllEpgLoadedListener { 
        void onLoaded(Map<String, List<EpgProgram>> allPrograms, Map<String, String> channelNameToId, Map<String, String> channelNameToIcon);
        void onError(String error);
    }
    private static Map<String, String> sAliasMap = null;
    private static Map<String, List<EpgProgram>> sAllPrograms = null;
    private static Map<String, String> sChannelNameToId = null;
    private static Map<String, String> sChannelNameToIcon = null;
    private static Map<String, String> sChannelNameToEpgid = null;
    private static AtomicBoolean sLoading = new AtomicBoolean(false);
    private static boolean sLoaded = false;
    private static List<OnAllEpgLoadedListener> sPendingListeners = new ArrayList<>();
    private static synchronized Map<String, String> loadAliasMap(Context context) {
        if (sAliasMap != null) return sAliasMap;
        Map<String, String> map = new HashMap<>();
        try {
            String json = null;
            String configDir = LogUtils.getConfigDir();
            if (!configDir.isEmpty()) {
                File extFile = new File(configDir, "epg_data.json");
                if (extFile.exists()) {
                    FileInputStream fis = new FileInputStream(extFile);
                    byte[] buffer = new byte[(int) extFile.length()];
                    fis.read(buffer);
                    fis.close();
                    json = new String(buffer, "UTF-8");
                    LogUtils.writeLog("从外部存储加载别名映射: " + extFile.getAbsolutePath());
                }
            }
            if (json == null) {
                InputStream is = context.getAssets().open("epg_data.json");
                byte[] buffer = new byte[is.available()];
                is.read(buffer);
                is.close();
                json = new String(buffer, "UTF-8");
                LogUtils.writeLog("从 assets 加载别名映射");
            }
            JSONArray epgs = null;
            try {
                epgs = new JSONArray(json);
            } catch (Exception e1) {
                try {
                    JSONObject root = new JSONObject(json);
                    epgs = root.getJSONArray("epgs");
                } catch (Exception e2) {
                    LogUtils.writeLog("加载别名映射失败: 无法解析 JSON 格式");
                    sAliasMap = map;
                    return map;
                }
            }
            if (epgs == null) {
                LogUtils.writeLog("加载别名映射失败: 未找到 epgs 数据");
                sAliasMap = map;
                return map;
            }
            for (int i = 0; i < epgs.length(); i++) {
                JSONObject obj = epgs.getJSONObject(i);
                String epgid = obj.getString("epgid");
                String nameStr = obj.getString("name");
                String[] names = nameStr.split(",");
                for (String name : names) {
                    String trimmed = name.trim();
                    if (trimmed.isEmpty()) continue;
                    map.put(trimmed, epgid);
                }
                String epgidTrim = epgid.trim();
                if (!epgidTrim.isEmpty()) {
                    map.put(epgidTrim, epgid);
                }
            }
            LogUtils.writeLog("别名映射加载完成，条目数: " + map.size());
        } catch (Exception e) {
            LogUtils.writeLog("加载别名映射失败: " + e.getMessage());
        }
        sAliasMap = map;
        return sAliasMap;
    }
    public static void loadAllEpg(Context context, String url, OnAllEpgLoadedListener listener) {
        loadAliasMap(context);
        if (sLoaded && sAllPrograms != null && sChannelNameToIcon != null) {
            listener.onLoaded(sAllPrograms, sChannelNameToId, sChannelNameToIcon);
            return;
        }
        sPendingListeners.add(listener);
        if (!sLoading.compareAndSet(false, true)) {
            return;
        }
        LogUtils.writeLog("开始全量加载并解析EPG...");
        new Thread(() -> {
            try {
                String cacheDir = LogUtils.getEpgCacheDir();
                File cacheDirFile = new File(cacheDir);
                if (!cacheDirFile.exists()) cacheDirFile.mkdirs();
                String hashFile = LogUtils.getEpgHashFile();
                File hashFileObj = new File(hashFile);
                String remoteHash = null;
                boolean useHash = true;
                try {
                    String hashUrl = url + ".hash";
                    OkHttpClient client = new OkHttpClient.Builder()
                            .connectTimeout(10, TimeUnit.SECONDS)
                            .readTimeout(10, TimeUnit.SECONDS)
                            .build();
                    Request request = new Request.Builder().url(hashUrl).header("User-Agent", "Mozilla/5.0").build();
                    Response response = client.newCall(request).execute();
                    if (response.isSuccessful()) {
                        remoteHash = response.body().string().trim();
                        LogUtils.writeLog("获取远程哈希成功: " + remoteHash);
                    } else {
                        useHash = false;
                        LogUtils.writeLog("远程哈希不存在，将直接下载EPG");
                    }
                    response.close();
                } catch (Exception e) {
                    useHash = false;
                    LogUtils.writeLog("获取远程哈希失败，将直接下载EPG: " + e.getMessage());
                }
                File cacheFile = null;
                boolean needDownload = true;
                if (useHash && remoteHash != null && hashFileObj.exists()) {
                    String localHash = new String(java.nio.file.Files.readAllBytes(hashFileObj.toPath())).trim();
                    if (localHash.equals(remoteHash)) {
                        for (File f : cacheDirFile.listFiles()) {
                            if (f.getName().endsWith(".xml")) {
                                cacheFile = f;
                                break;
                            }
                        }
                        if (cacheFile != null && cacheFile.exists()) {
                            needDownload = false;
                            LogUtils.writeLog("哈希匹配，使用缓存: " + cacheFile.getAbsolutePath());
                        }
                    }
                }
                if (needDownload) {
                    OkHttpClient client = new OkHttpClient.Builder()
                            .connectTimeout(30, TimeUnit.SECONDS)
                            .readTimeout(60, TimeUnit.SECONDS)
                            .build();
                    Request request = new Request.Builder().url(url).header("User-Agent", "Mozilla/5.0").build();
                    LogUtils.writeLog("下载EPG: " + url);
                    Response response = client.newCall(request).execute();
                    if (!response.isSuccessful()) throw new Exception("HTTP " + response.code());
                    for (File f : cacheDirFile.listFiles()) {
                        if (f.getName().endsWith(".xml")) f.delete();
                    }
                    String fileName = "epg_" + System.currentTimeMillis() + ".xml";
                    cacheFile = new File(cacheDirFile, fileName);
                    InputStream responseStream = response.body().byteStream();
                    FileOutputStream fos = new FileOutputStream(cacheFile);
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = responseStream.read(buffer)) != -1) fos.write(buffer, 0, len);
                    fos.close();
                    responseStream.close();
                    LogUtils.writeLog("EPG下载完成: " + cacheFile.getAbsolutePath());
                    if (useHash && remoteHash != null) {
                        FileOutputStream hfos = new FileOutputStream(hashFileObj);
                        hfos.write(remoteHash.getBytes());
                        hfos.close();
                        LogUtils.writeLog("更新本地哈希: " + remoteHash);
                    }
                }
                if (cacheFile == null || !cacheFile.exists()) {
                    throw new Exception("无法获取EPG缓存文件");
                }
                LogUtils.writeLog("开始解析EPG: " + cacheFile.getAbsolutePath());
                InputStream is = new FileInputStream(cacheFile);
                parseAllData(is);
                is.close();
                sLoaded = true;
                LogUtils.writeLog("EPG全量解析完成，共解析 " + (sAllPrograms != null ? sAllPrograms.size() : 0) + " 个频道");
                LogUtils.writeLog("图标映射数量: " + (sChannelNameToIcon != null ? sChannelNameToIcon.size() : 0));
                for (OnAllEpgLoadedListener l : sPendingListeners) {
                    android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                    mainHandler.post(() -> l.onLoaded(sAllPrograms, sChannelNameToId, sChannelNameToIcon));
                }
                sPendingListeners.clear();
            } catch (Exception e) {
                LogUtils.writeCrashLog(e);
                LogUtils.writeLog("全量加载EPG失败: " + e.getMessage());
                for (OnAllEpgLoadedListener l : sPendingListeners) {
                    android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                    mainHandler.post(() -> l.onError(e.getMessage()));
                }
                sPendingListeners.clear();
            } finally {
                sLoading.set(false);
            }
        }).start();
    }
    private static void parseAllData(InputStream is) throws XmlPullParserException, IOException, ParseException {
        Map<String, List<EpgProgram>> allPrograms = new HashMap<>();
        Map<String, String> channelNameToId = new HashMap<>();
        Map<String, String> channelNameToIcon = new HashMap<>();
        Map<String, String> channelNameToEpgid = new HashMap<>();
        XmlPullParser parser = Xml.newPullParser();
        parser.setInput(is, "UTF-8");
        int eventType = parser.getEventType();
        String currentTag = null;
        boolean inChannel = false;
        boolean inProgramme = false;
        String currentChannelId = null;
        String currentDisplayName = null;
        String currentIconUrl = null;
        String progChannelId = null;
        String progStart = null;
        String progStop = null;
        String progTitle = null;
        String progDesc = null;
        SimpleDateFormat sdfWithZone = new SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US);
        SimpleDateFormat sdfNoZone = new SimpleDateFormat("yyyyMMddHHmmss", Locale.US);
        Set<String> allChannelIds = new HashSet<>();
        while (eventType != XmlPullParser.END_DOCUMENT) {
            switch (eventType) {
                case XmlPullParser.START_TAG:
                    currentTag = parser.getName();
                    if ("channel".equals(currentTag)) {
                        inChannel = true;
                        currentChannelId = parser.getAttributeValue(null, "id");
                        if (currentChannelId != null) {
                            currentChannelId = currentChannelId.trim();
                            allChannelIds.add(currentChannelId);
                        }
                        currentDisplayName = null;
                        currentIconUrl = null;
                    } else if (inChannel && "display-name".equals(currentTag)) {
                        String text = parser.nextText().trim();
                        if (text != null && !text.isEmpty()) {
                            if (currentDisplayName == null) currentDisplayName = text;
                            else currentDisplayName += "," + text;
                        }
                    } else if (inChannel && "icon".equals(currentTag)) {
                        currentIconUrl = parser.getAttributeValue(null, "src");
                    } else if ("programme".equals(currentTag)) {
                        inProgramme = true;
                        progChannelId = parser.getAttributeValue(null, "channel");
                        if (progChannelId != null) progChannelId = progChannelId.trim();
                        progStart = parser.getAttributeValue(null, "start");
                        progStop = parser.getAttributeValue(null, "stop");
                        progTitle = null;
                        progDesc = null;
                    }
                    break;
                case XmlPullParser.TEXT:
                    if (inProgramme && parser.getText() != null) {
                        String text = parser.getText().trim();
                        if ("title".equals(currentTag)) {
                            if (progTitle == null) progTitle = text;
                            else progTitle += text;
                        } else if ("desc".equals(currentTag)) {
                            if (progDesc == null) progDesc = text;
                            else progDesc += text;
                        }
                    }
                    break;
                case XmlPullParser.END_TAG:
                    if ("channel".equals(parser.getName())) {
                        inChannel = false;
                        if (currentChannelId != null && !currentChannelId.isEmpty()) {
                            channelNameToId.put(currentChannelId, currentChannelId);
                            if (currentDisplayName != null && !currentDisplayName.isEmpty()) {
                                String[] names = currentDisplayName.split(",");
                                for (String name : names) {
                                    name = name.trim();
                                    if (name.isEmpty()) continue;
                                    channelNameToId.put(name, currentChannelId);
                                    if (currentIconUrl != null && !currentIconUrl.isEmpty() && !channelNameToIcon.containsKey(name)) {
                                        channelNameToIcon.put(name, currentIconUrl);
                                    }
                                }
                            }
                            if (currentIconUrl != null && !currentIconUrl.isEmpty() && currentDisplayName == null) {
                                channelNameToIcon.put(currentChannelId, currentIconUrl);
                            }
                        }
                    } else if ("programme".equals(parser.getName())) {
                        inProgramme = false;
                        if (progChannelId != null && !progChannelId.isEmpty() && progTitle != null && !progTitle.isEmpty()) {
                            EpgProgram prog = new EpgProgram();
                            prog.title = progTitle;
                            prog.desc = (progDesc != null) ? progDesc : "";
                            if (progStart != null && !progStart.isEmpty()) {
                                try { prog.startTime = sdfWithZone.parse(progStart).getTime(); }
                                catch (ParseException e) { try { prog.startTime = sdfNoZone.parse(progStart).getTime(); } catch (ParseException ignored) {} }
                            }
                            if (progStop != null && !progStop.isEmpty()) {
                                try { prog.endTime = sdfWithZone.parse(progStop).getTime(); }
                                catch (ParseException e) { try { prog.endTime = sdfNoZone.parse(progStop).getTime(); } catch (ParseException ignored) {} }
                            }
                            List<EpgProgram> list = allPrograms.get(progChannelId);
                            if (list == null) { list = new ArrayList<>(); allPrograms.put(progChannelId, list); }
                            list.add(prog);
                        }
                    }
                    break;
            }
            eventType = parser.next();
        }
        for (String id : allChannelIds) {
            if (!channelNameToId.containsValue(id)) {
                channelNameToId.put(id, id);
            }
        }
        if (sAliasMap != null) {
            int successCount = 0;
            int failCount = 0;
            for (Map.Entry<String, String> entry : sAliasMap.entrySet()) {
                String alias = entry.getKey();
                String epgid = entry.getValue();
                String realId = channelNameToId.get(epgid);
                if (realId == null) {
                    LogUtils.writeLog("别名映射失败: " + alias + " (epgid: " + epgid + " 未找到对应的 display-name)");
                    failCount++;
                    continue;
                }
                channelNameToId.put(alias, realId);
                channelNameToEpgid.put(alias, epgid);
                successCount++;
            }
            LogUtils.writeLog("别名映射统计: 成功 " + successCount + " 个，失败 " + failCount + " 个");
        }
        sAllPrograms = allPrograms;
        sChannelNameToId = channelNameToId;
        sChannelNameToIcon = channelNameToIcon;
        sChannelNameToEpgid = channelNameToEpgid;
        LogUtils.writeLog("缓存构建完成：频道数=" + sAllPrograms.size() + ", 名称映射=" + sChannelNameToId.size() + ", 图标映射=" + sChannelNameToIcon.size() + ", epgid映射=" + sChannelNameToEpgid.size());
    }
    public static List<EpgProgram> getProgramsForChannel(String channelName) {
        if (sAllPrograms == null || sChannelNameToId == null) return new ArrayList<>();
        String channelId = sChannelNameToId.get(channelName);
        if (channelId == null) {
            LogUtils.writeLog("getProgramsForChannel: 未找到频道ID: " + channelName);
            return new ArrayList<>();
        }
        List<EpgProgram> result = sAllPrograms.get(channelId);
        if (result == null) {
            LogUtils.writeLog("getProgramsForChannel: 频道 " + channelName + " (id=" + channelId + ") 无节目数据");
            return new ArrayList<>();
        }
        long currentTime = System.currentTimeMillis();
        Collections.sort(result, (o1, o2) -> Long.compare(o1.startTime, o2.startTime));
        int currentIndex = 0;
        for (int i = 0; i < result.size(); i++) {
            if (result.get(i).endTime > currentTime) {
                currentIndex = i;
                break;
            }
        }
        if (currentIndex > 0 && currentIndex < result.size()) {
            List<EpgProgram> sortedList = new ArrayList<>();
            for (int i = currentIndex; i < result.size(); i++) sortedList.add(result.get(i));
            for (int i = 0; i < currentIndex; i++) sortedList.add(result.get(i));
            result = sortedList;
        }
        LogUtils.writeLog("getProgramsForChannel: " + channelName + " 返回 " + result.size() + " 个节目");
        return result;
    }
    public static Map<String, List<EpgProgram>> getAllPrograms() {
        if (sAllPrograms == null || sChannelNameToId == null) return new HashMap<>();
        Map<String, List<EpgProgram>> nameMap = new HashMap<>();
        for (Map.Entry<String, String> entry : sChannelNameToId.entrySet()) {
            String channelName = entry.getKey();
            String channelId = entry.getValue();
            List<EpgProgram> list = sAllPrograms.get(channelId);
            if (list != null) {
                nameMap.put(channelName, list);
            }
        }
        return nameMap;
    }
    public static Map<String, String> getChannelNameToIcon() {
        return sChannelNameToIcon != null ? sChannelNameToIcon : new HashMap<>();
    }
    public static Map<String, String> getChannelNameToEpgid() {
        return sChannelNameToEpgid != null ? sChannelNameToEpgid : new HashMap<>();
    }
    public static class EpgProgram {
        public long startTime;
        public long endTime;
        public String title;
        public String desc;
        @Override
        public String toString() {
            return "EpgProgram{" +
                    "startTime=" + startTime +
                    ", endTime=" + endTime +
                    ", title='" + title + '\'' +
                    ", desc='" + desc + '\'' +
                    '}';
        }
    }
}
EPG

# ---------- MainActivity.java ----------
cat > "$TEMPLATE_DIR/src/MainActivity.java" <<'MAIN'
package com.whyun.witv;
import android.Manifest;
import android.app.ProgressDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.preference.PreferenceManager;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.PlayerView;
import com.whyun.witv.source.SourceManager;
import com.whyun.witv.epg.EPGParser;
import com.whyun.witv.player.PlayerConfigManager;
import com.whyun.witv.favorite.FavoriteManager;
import com.whyun.witv.utils.LogUtils;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.URLDecoder;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class MainActivity extends AppCompatActivity {
    private static final int REQUEST_PERMISSIONS = 100;
    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> currentChannelList = new ArrayList<>();
    private Map<String, List<SourceManager.Channel>> groupMap = new HashMap<>();
    private List<String> groupNames = new ArrayList<>();
    private String currentGroup = "";
    private String currentSubUrl = "";
    private String currentSubName = "";
    private RecyclerView subRecycler, groupRecycler, channelRecycler;
    private RecyclerView scheduleChannelRecycler, scheduleEpgRecycler;
    private SubAdapter subAdapter;
    private GroupAdapter groupAdapter;
    private ChannelAdapter channelAdapter;
    private ScheduleChannelAdapter scheduleChannelAdapter;
    private ScheduleEpgAdapter scheduleEpgAdapter;
    private View overlayContainer, overlayLayout, scheduleLayout;
    private SharedPreferences prefs;
    private ConfigurationManager config;
    private boolean isOverlayVisible = false;
    private Set<String> favoriteSet = new HashSet<>();
    private static final String KEY_FAVORITES = "favorites";
    private static final String KEY_SUB_LIST = "sub_list";
    private static final String KEY_SELECTED_SUBS = "selected_subs";
    private static final String KEY_LAST_CHANNEL = "last_channel";
    private static final String KEY_LAST_GROUP = "last_group";
    private static final String KEY_AUTO_RECONNECT = "auto_reconnect";
    private static final String KEY_NEED_RELOAD = "need_reload";
    private static final String KEY_SHOW_SPEED = "show_speed";
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    private File logoDir;
    private Runnable hideOverlayRunnable;
    private boolean isLoading = false;
    private List<SubEntry> subEntryList = new ArrayList<>();
    private List<EPGParser.EpgProgram> currentEpgList = new ArrayList<>();
    private ProgressDialog progressDialog;
    private boolean loadFinished = false;
    private Set<String> selectedSubs = new HashSet<>();
    private Button btnEpgSchedule;
    private boolean isScheduleMode = false;
    private String currentScheduleChannelName = "";
    private List<EPGParser.EpgProgram> currentScheduleEpg = new ArrayList<>();
    private int selectedDayIndex = 0;
    private List<String> dayLabels = new ArrayList<>();
    private LinearLayoutManager scheduleEpgLayoutManager;
    private LinearLayout dayTabs;
    private View leftClickArea;
    private Map<String, List<EPGParser.EpgProgram>> epgCacheMap = new HashMap<>();
    private Map<String, String> epgIconMap = new HashMap<>();
    private Map<String, String> epgIdMap = new HashMap<>();
    private boolean epgLoaded = false;
    private boolean isReconnecting = false;
    private int reconnectAttempts = 0;
    private ExecutorService logoDownloadExecutor = Executors.newFixedThreadPool(4);
    private AtomicInteger logoDownloadCounter = new AtomicInteger(0);
    private int totalChannelsForLogo = 0;
    private boolean isLogoDownloading = false;
    private AlertDialog noSourceDialog = null;
    static class SubEntry { String name; String url; }
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            try { LogUtils.writeCrashLog(throwable); } catch (Exception ignored) {}
            android.os.Process.killProcess(android.os.Process.myPid());
            System.exit(1);
        });
        try { Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Exception e) {}
        super.onCreate(savedInstanceState);
        LogUtils.init(this);
        LogUtils.writeLog("=== 应用启动 ===");
        copyConfigFiles();
        String logDir = LogUtils.getLogDir();
        if (!logDir.isEmpty()) {
            Toast.makeText(this, "日志目录: " + logDir, Toast.LENGTH_LONG).show();
        } else {
            Toast.makeText(this, "日志目录创建失败", Toast.LENGTH_LONG).show();
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this,
                        new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE,
                                Manifest.permission.READ_EXTERNAL_STORAGE},
                        REQUEST_PERMISSIONS);
            }
        }
        try {
            setContentView(R.layout.activity_main);
            Toast.makeText(this, "界面加载完成", Toast.LENGTH_SHORT).show();
            LogUtils.writeLog("界面加载完成");
            config = ConfigurationManager.getInstance(this);
            PlayerConfigManager.init(this);
            FavoriteManager.init(this);
            prefs = PreferenceManager.getDefaultSharedPreferences(this);
            if (!prefs.contains(KEY_AUTO_RECONNECT)) {
                prefs.edit().putBoolean(KEY_AUTO_RECONNECT, true).apply();
            }
            if (!prefs.contains(KEY_SHOW_SPEED)) {
                prefs.edit().putBoolean(KEY_SHOW_SPEED, true).apply();
            }
            favoriteSet = new HashSet<>(prefs.getStringSet(KEY_FAVORITES, new HashSet<>()));
            String root = LogUtils.getAppRootDir();
            if (!root.isEmpty()) {
                logoDir = new File(root, "logo");
                if (!logoDir.exists()) logoDir.mkdirs();
            } else {
                File baseDir = new File(Environment.getExternalStorageDirectory(), "witv");
                if (!baseDir.exists()) baseDir.mkdirs();
                logoDir = new File(baseDir, "logo");
                if (!logoDir.exists()) logoDir.mkdirs();
            }
            deleteOldLogos();
            selectedSubs = new HashSet<>(prefs.getStringSet(KEY_SELECTED_SUBS, new HashSet<>()));
            if (selectedSubs.isEmpty()) {
                LogUtils.writeLog("无订阅源，跳转到设置界面");
                Intent intent = new Intent(this, SettingsActivity.class);
                intent.putExtra("open_tab", 3);
                startActivity(intent);
            }
            String epgUrlPref = prefs.getString("epg_url", null);
            if (epgUrlPref == null || epgUrlPref.isEmpty()) {
                String configEpg = config.getString("EPG_URLS", null);
                if (configEpg != null && !configEpg.isEmpty()) {
                    prefs.edit().putString("epg_url", configEpg).apply();
                    LogUtils.writeLog("已从配置加载 EPG_URL: " + configEpg);
                    Toast.makeText(this, "EPG地址已自动配置", Toast.LENGTH_SHORT).show();
                }
            }
            playerView = findViewById(R.id.player_container);
            overlayContainer = findViewById(R.id.overlay_container);
            overlayLayout = findViewById(R.id.overlay_layout);
            scheduleLayout = findViewById(R.id.schedule_layout);
            subRecycler = findViewById(R.id.sub_recycler);
            groupRecycler = findViewById(R.id.group_recycler);
            channelRecycler = findViewById(R.id.channel_recycler);
            scheduleChannelRecycler = findViewById(R.id.schedule_channel_recycler);
            scheduleEpgRecycler = findViewById(R.id.schedule_epg_recycler);
            btnEpgSchedule = findViewById(R.id.btn_epg_schedule);
            dayTabs = findViewById(R.id.day_tabs);
            leftClickArea = findViewById(R.id.left_click_area);
            subRecycler.setLayoutManager(new LinearLayoutManager(this));
            groupRecycler.setLayoutManager(new LinearLayoutManager(this));
            channelRecycler.setLayoutManager(new LinearLayoutManager(this));
            scheduleChannelRecycler.setLayoutManager(new LinearLayoutManager(this));
            scheduleEpgLayoutManager = new LinearLayoutManager(this);
            scheduleEpgRecycler.setLayoutManager(scheduleEpgLayoutManager);
            loadSubscriptions();
            subAdapter = new SubAdapter(subEntryList, selectedSubs, entry -> {
                String key = entry.name + "||" + entry.url;
                if (selectedSubs.contains(key)) {
                    selectedSubs.remove(key);
                } else {
                    selectedSubs.add(key);
                }
                prefs.edit().putStringSet(KEY_SELECTED_SUBS, selectedSubs).apply();
                subAdapter.notifyDataSetChanged();
                loadSelectedSources();
            });
            subRecycler.setAdapter(subAdapter);
            groupAdapter = new GroupAdapter(new ArrayList<>(), group -> {
                currentGroup = group;
                showChannelsForGroup(group);
                groupAdapter.setSelectedGroup(group);
            });
            groupRecycler.setAdapter(groupAdapter);
            channelAdapter = new ChannelAdapter(new ArrayList<>(), favoriteSet, logoDir,
                channel -> {
                    playChannel(channel);
                    channelAdapter.setSelectedChannel(channel);
                    if (isScheduleMode) {
                        showScheduleForChannel(channel);
                    }
                },
                this::toggleFavorite,
                this,
                epgCacheMap
            );
            channelRecycler.setAdapter(channelAdapter);
            scheduleChannelAdapter = new ScheduleChannelAdapter(new ArrayList<>(), favoriteSet, logoDir, this, channel -> {
                showScheduleForChannel(channel);
            });
            scheduleChannelRecycler.setAdapter(scheduleChannelAdapter);
            scheduleEpgAdapter = new ScheduleEpgAdapter(new ArrayList<>());
            scheduleEpgRecycler.setAdapter(scheduleEpgAdapter);
            playerView.setOnTouchListener((v, event) -> {
                if (event.getAction() == MotionEvent.ACTION_UP) {
                    float y = event.getY();
                    float height = v.getHeight();
                    if (y > height * 0.5 && y < height * 0.85) {
                        showInfoPopup();
                        return true;
                    }
                }
                return false;
            });
            btnEpgSchedule.setOnClickListener(v -> toggleScheduleMode());
            findViewById(R.id.schedule_close_area).setOnClickListener(v -> toggleScheduleMode());
            leftClickArea.setOnClickListener(v -> {
                if (isScheduleMode) {
                    toggleScheduleMode();
                    mainHandler.postDelayed(() -> showOverlay(), 100);
                } else {
                    showOverlay();
                }
            });
            String epgUrl = prefs.getString("epg_url", null);
            if (epgUrl == null || epgUrl.isEmpty()) {
                epgUrl = config.getString("EPG_URLS", null);
            }
            if (epgUrl != null && !epgUrl.isEmpty()) {
                LogUtils.writeLog("开始全量加载EPG...");
                EPGParser.loadAllEpg(this, epgUrl, new EPGParser.OnAllEpgLoadedListener() {
                    @Override
                    public void onLoaded(Map<String, List<EPGParser.EpgProgram>> allPrograms, Map<String, String> channelNameToId, Map<String, String> channelNameToIcon) {
                        runOnUiThread(() -> {
                            epgCacheMap.clear();
                            epgIconMap.clear();
                            epgIdMap.clear();
                            epgIdMap.putAll(EPGParser.getChannelNameToEpgid());
                            for (Map.Entry<String, String> entry : channelNameToId.entrySet()) {
                                String name = entry.getKey();
                                String id = entry.getValue();
                                List<EPGParser.EpgProgram> list = allPrograms.get(id);
                                if (list != null) {
                                    Collections.sort(list, (o1, o2) -> Long.compare(o1.startTime, o2.startTime));
                                    epgCacheMap.put(name, list);
                                }
                            }
                            epgIconMap.putAll(channelNameToIcon);
                            epgLoaded = true;
                            LogUtils.writeLog("全量EPG加载完成，缓存频道数: " + epgCacheMap.size() + ", 图标数: " + epgIconMap.size());
                            channelAdapter.notifyDataSetChanged();
                            scheduleChannelAdapter.notifyDataSetChanged();
                            if (currentChannel != null && epgCacheMap.containsKey(currentChannel.name)) {
                                currentEpgList = EPGParser.getProgramsForChannel(currentChannel.name);
                            }
                            if (!isLogoDownloading && !groupMap.isEmpty()) {
                                downloadAllLogos();
                            }
                        });
                    }
                    @Override
                    public void onError(String error) {
                        runOnUiThread(() -> {
                            LogUtils.writeLog("全量EPG加载失败: " + error);
                            Toast.makeText(MainActivity.this, "EPG加载失败: " + error, Toast.LENGTH_SHORT).show();
                        });
                    }
                });
            }
            if (prefs.getBoolean(KEY_NEED_RELOAD, false)) {
                prefs.edit().remove(KEY_NEED_RELOAD).apply();
                loadSelectedSources();
            }
            mainHandler.postDelayed(() -> {
                if (selectedSubs.isEmpty()) {
                    for (SubEntry se : subEntryList) {
                        if (!"我的收藏".equals(se.name) && se.url != null && !se.url.isEmpty()) {
                            String key = se.name + "||" + se.url;
                            selectedSubs.add(key);
                            prefs.edit().putStringSet(KEY_SELECTED_SUBS, selectedSubs).apply();
                            subAdapter.notifyDataSetChanged();
                            break;
                        }
                    }
                }
                if (!selectedSubs.isEmpty()) {
                    dismissNoSourceDialog();
                    loadSelectedSources();
                } else {
                    LogUtils.writeLog("没有可用的订阅源，显示引导对话框");
                    showNoSourceDialog();
                }
            }, 500);
            hideOverlayRunnable = () -> {
                if (isOverlayVisible) hideOverlay();
            };
            LogUtils.writeLog("应用启动成功");
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            showFatalErrorDialog("初始化失败: " + e.getMessage());
        }
    }
    private void deleteOldLogos() {
        if (logoDir == null || !logoDir.exists()) return;
        File[] files = logoDir.listFiles();
        if (files == null) return;
        for (File f : files) {
            String name = f.getName();
            if (name.matches("^-?\\d+\\.png$")) {
                f.delete();
                LogUtils.writeLog("删除旧图标: " + f.getAbsolutePath());
            }
        }
    }
    private void copyConfigFiles() {
        try {
            String configDir = LogUtils.getConfigDir();
            if (configDir.isEmpty()) return;
            File dir = new File(configDir);
            if (!dir.exists()) dir.mkdirs();
            String[] files = {"configuration.json", "epg_data.json"};
            for (String fname : files) {
                InputStream is = getAssets().open(fname);
                File outFile = new File(dir, fname);
                FileOutputStream fos = new FileOutputStream(outFile);
                byte[] buffer = new byte[8192];
                int len;
                while ((len = is.read(buffer)) != -1) fos.write(buffer, 0, len);
                fos.close();
                is.close();
                LogUtils.writeLog("复制配置文件: " + outFile.getAbsolutePath());
            }
        } catch (Exception e) {
            LogUtils.writeLog("复制配置文件失败: " + e.getMessage());
        }
    }
    private void dismissNoSourceDialog() {
        if (noSourceDialog != null && noSourceDialog.isShowing()) {
            noSourceDialog.dismiss();
            noSourceDialog = null;
        }
    }
    private void loadSelectedSources() {
        if (selectedSubs.isEmpty()) {
            showNoSourceDialog();
            return;
        }
        dismissNoSourceDialog();
        for (String key : selectedSubs) {
            String[] parts = key.split("\\|\\|");
            if (parts.length == 2) {
                currentSubName = parts[0];
                currentSubUrl = parts[1];
                break;
            }
        }
        if (currentSubUrl != null && !currentSubUrl.isEmpty()) {
            showLoadingDialog("正在加载订阅源...");
            loadSourceForUrl(currentSubUrl);
        } else {
            showNoSourceDialog();
        }
    }
    private void loadSourceForUrl(String url) {
        if (isLoading || url == null || url.isEmpty()) {
            if (url == null || url.isEmpty()) {
                showNoSourceDialog();
            }
            return;
        }
        isLoading = true;
        loadFinished = false;
        if (url.contains("$")) url = url.substring(0, url.indexOf("$"));
        final String finalUrl = url;
        LogUtils.writeLog("开始加载源: " + finalUrl);
        Toast.makeText(this, "正在加载: " + finalUrl, Toast.LENGTH_SHORT).show();
        mainHandler.postDelayed(() -> {
            if (!loadFinished) {
                isLoading = false;
                dismissLoadingDialog();
                LogUtils.writeLog("加载源超时");
                showLoadErrorDialog("加载超时，请检查网络或源地址是否有效。");
            }
        }, 30000);
        new SourceManager(this).loadFromUrl(finalUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(Map<String, List<SourceManager.Channel>> map, List<String> names) {
                loadFinished = true;
                isLoading = false;
                dismissLoadingDialog();
                try {
                    groupMap = map;
                    groupNames = names;
                    groupAdapter.updateData(groupNames);
                    String lastGroup = prefs.getString(KEY_LAST_GROUP, "");
                    if (!lastGroup.isEmpty() && groupNames.contains(lastGroup)) {
                        currentGroup = lastGroup;
                    } else if (!groupNames.isEmpty()) {
                        currentGroup = groupNames.get(0);
                    }
                    if (!currentGroup.isEmpty()) {
                        groupAdapter.setSelectedGroup(currentGroup);
                        showChannelsForGroup(currentGroup);
                    } else {
                        currentChannelList.clear();
                        channelAdapter.updateData(currentChannelList);
                        Toast.makeText(MainActivity.this, "解析成功但无频道数据", Toast.LENGTH_LONG).show();
                    }
                    showOverlay();
                    resetAutoHideTimer();
                    LogUtils.writeLog("源加载成功，分组数: " + (map != null ? map.size() : 0));
                    if (!isLogoDownloading) {
                        downloadAllLogos();
                    }
                } catch (Exception e) {
                    LogUtils.writeCrashLog(e);
                    showLoadErrorDialog("数据处理异常: " + e.getMessage());
                }
            }
            @Override
            public void onError(String error) {
                loadFinished = true;
                isLoading = false;
                dismissLoadingDialog();
                LogUtils.writeLog("加载源失败: " + error);
                showLoadErrorDialog(error);
            }
        });
    }
    private void downloadAllLogos() {
        if (isLogoDownloading) return;
        if (groupMap == null || groupMap.isEmpty()) {
            LogUtils.writeLog("groupMap为空，跳过台标下载");
            return;
        }
        isLogoDownloading = true;
        List<SourceManager.Channel> allChannels = new ArrayList<>();
        for (List<SourceManager.Channel> list : groupMap.values()) {
            allChannels.addAll(list);
        }
        totalChannelsForLogo = allChannels.size();
        logoDownloadCounter.set(0);
        LogUtils.writeLog("开始批量处理台标，总频道数: " + totalChannelsForLogo);
        for (SourceManager.Channel ch : allChannels) {
            logoDownloadExecutor.execute(() -> {
                processChannelLogo(ch);
                int done = logoDownloadCounter.incrementAndGet();
                if (done % 50 == 0 || done == totalChannelsForLogo) {
                    LogUtils.writeLog("台标处理进度: " + done + "/" + totalChannelsForLogo);
                }
            });
        }
        mainHandler.postDelayed(() -> {
            isLogoDownloading = false;
            LogUtils.writeLog("批量台标处理完成，共处理 " + logoDownloadCounter.get() + " 个频道");
            runOnUiThread(() -> {
                channelAdapter.notifyDataSetChanged();
                scheduleChannelAdapter.notifyDataSetChanged();
            });
        }, 30000);
    }
    public void processChannelLogo(SourceManager.Channel channel) {
        if (channel == null) return;
        String epgid = epgIdMap.get(channel.name);
        String fileName;
        if (epgid != null && !epgid.isEmpty()) {
            fileName = epgid.replace("/", "_").replace("\\", "_") + ".png";
        } else {
            fileName = channel.name.hashCode() + ".png";
        }
        final File logoFile = new File(logoDir, fileName);
        if (logoFile.exists()) {
            return;
        }
        String logoUrl = null;
        if (epgIconMap.containsKey(channel.name)) {
            logoUrl = epgIconMap.get(channel.name);
        }
        if (logoUrl == null || logoUrl.isEmpty()) {
            logoUrl = channel.logoUrl;
        }
        if (logoUrl != null && !logoUrl.isEmpty()) {
            downloadAndProcessLogo(channel, logoUrl, logoFile);
        }
    }
    private void downloadAndProcessLogo(SourceManager.Channel channel, String logoUrl, File logoFile) {
        try {
            String decodedUrl = URLDecoder.decode(logoUrl, "UTF-8");
            OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                    .build();
            Request request = new Request.Builder().url(decodedUrl).build();
            Response response = client.newCall(request).execute();
            if (response.code() == 200) {
                InputStream is = response.body().byteStream();
                Bitmap src = BitmapFactory.decodeStream(is);
                is.close();
                if (src == null) {
                    return;
                }
                int targetWidth = 120;
                int targetHeight = (int) ((float) targetWidth / src.getWidth() * src.getHeight());
                if (targetHeight > 80) targetHeight = 80;
                Bitmap scaled = Bitmap.createScaledBitmap(src, targetWidth, targetHeight, true);
                src.recycle();
                Bitmap processed = makeTransparent(scaled);
                scaled.recycle();
                if (!logoDir.exists()) logoDir.mkdirs();
                FileOutputStream fos = new FileOutputStream(logoFile);
                processed.compress(Bitmap.CompressFormat.PNG, 100, fos);
                fos.close();
                processed.recycle();
                LogUtils.writeLog("台标下载并处理成功: " + logoFile.getAbsolutePath());
                runOnUiThread(() -> {
                    channelAdapter.notifyDataSetChanged();
                    scheduleChannelAdapter.notifyDataSetChanged();
                });
            } else {
                LogUtils.writeLog("台标下载失败 HTTP " + response.code());
            }
            response.close();
        } catch (Exception e) {
            LogUtils.writeLog("台标下载异常: " + e.getMessage());
        }
    }
    private Bitmap makeTransparent(Bitmap src) {
        int width = src.getWidth();
        int height = src.getHeight();
        Bitmap result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
                int pixel = src.getPixel(x, y);
                int r = Color.red(pixel);
                int g = Color.green(pixel);
                int b = Color.blue(pixel);
                if (r > 220 && g > 220 && b > 220) {
                    result.setPixel(x, y, Color.TRANSPARENT);
                } else {
                    result.setPixel(x, y, pixel);
                }
            }
        }
        return result;
    }
    private void showChannelsForGroup(String group) {
        try {
            List<SourceManager.Channel> list;
            if ("我的收藏".equals(group)) {
                list = new ArrayList<>();
                if (groupMap != null) {
                    for (List<SourceManager.Channel> clist : groupMap.values()) {
                        for (SourceManager.Channel ch : clist) {
                            if (favoriteSet.contains(ch.name)) {
                                list.add(ch);
                            }
                        }
                    }
                }
            } else {
                list = groupMap.get(group);
                if (list == null) list = new ArrayList<>();
            }
            currentChannelList = list;
            channelAdapter.updateData(currentChannelList);
            scheduleChannelAdapter.updateData(currentChannelList);
            String lastChannel = prefs.getString(KEY_LAST_CHANNEL, "");
            SourceManager.Channel target = null;
            if (!lastChannel.isEmpty()) {
                for (SourceManager.Channel ch : currentChannelList) {
                    if (ch.name.equals(lastChannel)) {
                        target = ch;
                        break;
                    }
                }
            }
            if (target == null && !currentChannelList.isEmpty()) {
                target = currentChannelList.get(0);
            }
            if (target != null) {
                channelAdapter.setSelectedChannel(target);
                playChannel(target);
            } else {
                Toast.makeText(this, "该分组无频道", Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "显示分组异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    private void playChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentChannel = channel;
        reconnectAttempts = 0;
        isReconnecting = false;
        prefs.edit().putString(KEY_LAST_CHANNEL, channel.name).apply();
        prefs.edit().putString(KEY_LAST_GROUP, currentGroup).apply();
        try {
            if (player == null) {
                DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
                androidx.media3.exoplayer.DefaultLoadControl loadControl = new androidx.media3.exoplayer.DefaultLoadControl.Builder()
                        .setBufferDurationsMs(120000, 180000, 5000, 10000)
                        .build();
                player = new ExoPlayer.Builder(this)
                        .setTrackSelector(trackSelector)
                        .setLoadControl(loadControl)
                        .build();
                playerView.setPlayer(player);
                player.addListener(new Player.Listener() {
                    @Override
                    public void onPlayerError(PlaybackException error) {
                        runOnUiThread(() -> {
                            LogUtils.writeCrashLog(error);
                            Toast.makeText(MainActivity.this, "播放错误: " + error.getMessage(), Toast.LENGTH_SHORT).show();
                            if (prefs.getBoolean(KEY_AUTO_RECONNECT, true) && currentChannel != null && !isReconnecting) {
                                isReconnecting = true;
                                reconnectAttempts++;
                                LogUtils.writeLog("尝试重连，次数: " + reconnectAttempts);
                                mainHandler.postDelayed(() -> {
                                    if (player != null && currentChannel != null) {
                                        player.setMediaItem(MediaItem.fromUri(currentChannel.url));
                                        player.prepare();
                                        player.play();
                                        isReconnecting = false;
                                        Toast.makeText(MainActivity.this, "已重连", Toast.LENGTH_SHORT).show();
                                    }
                                }, 1000);
                            }
                        });
                    }
                    @Override
                    public void onPlaybackStateChanged(int state) {
                        if (state == Player.STATE_ENDED) {
                            runOnUiThread(() -> {
                                if (player != null && currentChannel != null) {
                                    player.prepare();
                                    player.play();
                                }
                            });
                        }
                    }
                });
            }
            player.setMediaItem(MediaItem.fromUri(channel.url));
            player.prepare();
            player.play();
            if (epgLoaded) {
                currentEpgList = EPGParser.getProgramsForChannel(channel.name);
                LogUtils.writeLog("当前频道EPG节目数: " + currentEpgList.size());
            }
            LogUtils.writeLog("播放频道: " + channel.name + " URL: " + channel.url);
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "播放异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    private void toggleFavorite(SourceManager.Channel channel) {
        try {
            if (favoriteSet.contains(channel.name)) {
                favoriteSet.remove(channel.name);
            } else {
                favoriteSet.add(channel.name);
            }
            prefs.edit().putStringSet(KEY_FAVORITES, favoriteSet).apply();
            showChannelsForGroup(currentGroup);
            channelAdapter.updateFavorites(favoriteSet);
            scheduleChannelAdapter.updateFavorites(favoriteSet);
            Toast.makeText(this, favoriteSet.contains(channel.name) ? "已收藏" : "已取消收藏", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "收藏操作异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    private void showOverlay() {
        if (isScheduleMode) {
            scheduleLayout.setVisibility(View.GONE);
            isScheduleMode = false;
        }
        isOverlayVisible = true;
        overlayContainer.setVisibility(View.VISIBLE);
        overlayLayout.setVisibility(View.VISIBLE);
        scheduleLayout.setVisibility(View.GONE);
        resetAutoHideTimer();
    }
    private void hideOverlay() {
        isOverlayVisible = false;
        overlayContainer.setVisibility(View.GONE);
        overlayLayout.setVisibility(View.GONE);
        scheduleLayout.setVisibility(View.GONE);
        mainHandler.removeCallbacks(hideOverlayRunnable);
    }
    private void resetAutoHideTimer() {
        mainHandler.removeCallbacks(hideOverlayRunnable);
        if (isOverlayVisible) {
            mainHandler.postDelayed(hideOverlayRunnable, 5000);
        }
    }
    private void toggleScheduleMode() {
        if (isScheduleMode) {
            scheduleLayout.setVisibility(View.GONE);
            isScheduleMode = false;
            if (isOverlayVisible) {
                overlayLayout.setVisibility(View.VISIBLE);
            } else {
                showOverlay();
            }
        } else {
            if (currentChannel == null) {
                Toast.makeText(this, "请先选择一个频道", Toast.LENGTH_SHORT).show();
                return;
            }
            overlayLayout.setVisibility(View.GONE);
            isOverlayVisible = false;
            overlayContainer.setVisibility(View.VISIBLE);
            scheduleLayout.setVisibility(View.VISIBLE);
            isScheduleMode = true;
            showScheduleForChannel(currentChannel);
        }
    }
    private void showScheduleForChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentScheduleChannelName = channel.name;
        if (epgLoaded && epgCacheMap.containsKey(channel.name)) {
            currentScheduleEpg = epgCacheMap.get(channel.name);
            generateDayTabs(currentScheduleEpg);
            selectedDayIndex = 0;
            showDayPrograms(0);
            return;
        }
        Toast.makeText(this, "EPG数据未加载", Toast.LENGTH_SHORT).show();
    }
    private void generateDayTabs(List<EPGParser.EpgProgram> programs) {
        if (programs == null || programs.isEmpty()) {
            dayLabels.clear();
            dayTabs.removeAllViews();
            return;
        }
        Collections.sort(programs, (o1, o2) -> Long.compare(o1.startTime, o2.startTime));
        Set<String> dateSet = new HashSet<>();
        SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMdd", Locale.getDefault());
        for (EPGParser.EpgProgram prog : programs) {
            String date = sdf.format(new Date(prog.startTime));
            dateSet.add(date);
        }
        List<String> dates = new ArrayList<>(dateSet);
        Collections.sort(dates);
        String todayKey = sdf.format(new Date());
        List<String> filtered = new ArrayList<>();
        boolean foundToday = false;
        for (String d : dates) {
            if (d.equals(todayKey)) foundToday = true;
            if (foundToday && filtered.size() < 7) {
                filtered.add(d);
            }
        }
        if (filtered.isEmpty() && !dates.isEmpty()) {
            filtered.add(dates.get(0));
        }
        dayLabels = filtered;
        dayTabs.removeAllViews();
        String[] weekDays = {"周日","周一","周二","周三","周四","周五","周六"};
        for (int i = 0; i < dayLabels.size(); i++) {
            String dateKey = dayLabels.get(i);
            String label = "";
            try {
                SimpleDateFormat sdf2 = new SimpleDateFormat("yyyyMMdd", Locale.getDefault());
                Date d = sdf2.parse(dateKey);
                Calendar c = Calendar.getInstance();
                c.setTime(d);
                int dayOfWeek = c.get(Calendar.DAY_OF_WEEK) - 1;
                if (dateKey.equals(todayKey)) {
                    label = "今天";
                } else {
                    label = weekDays[dayOfWeek];
                }
            } catch (Exception e) {
                label = dateKey;
            }
            TextView tv = new TextView(this);
            tv.setText(label);
            tv.setTextColor(i == selectedDayIndex ? 0xFFFFD700 : 0xFFFFFFFF);
            tv.setTextSize(14);
            tv.setPadding(16, 8, 16, 8);
            tv.setBackgroundColor(i == selectedDayIndex ? 0x3300A0FF : 0x00000000);
            final int index = i;
            tv.setOnClickListener(v -> {
                selectedDayIndex = index;
                showDayPrograms(index);
                for (int j = 0; j < dayTabs.getChildCount(); j++) {
                    TextView child = (TextView) dayTabs.getChildAt(j);
                    child.setTextColor(j == index ? 0xFFFFD700 : 0xFFFFFFFF);
                    child.setBackgroundColor(j == index ? 0x3300A0FF : 0x00000000);
                }
            });
            dayTabs.addView(tv);
        }
    }
    private void showDayPrograms(int dayIndex) {
        if (dayIndex < 0 || dayIndex >= dayLabels.size()) return;
        String targetDate = dayLabels.get(dayIndex);
        SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMdd", Locale.getDefault());
        List<EPGParser.EpgProgram> dayPrograms = new ArrayList<>();
        long currentTime = System.currentTimeMillis();
        for (EPGParser.EpgProgram prog : currentScheduleEpg) {
            String date = sdf.format(new Date(prog.startTime));
            if (date.equals(targetDate)) {
                dayPrograms.add(prog);
            }
        }
        scheduleEpgAdapter.setItems(dayPrograms, currentTime);
        scheduleEpgRecycler.scrollToPosition(0);
    }

    // ==================== 酷9风格信息弹窗（居中偏下，含进度条和网速） ====================
    private void showInfoPopup() {
        if (currentChannel == null) return;
        try {
            View popupView = getLayoutInflater().inflate(R.layout.popup_info, null);
            ImageView ivLogo = popupView.findViewById(R.id.popup_logo);
            TextView tvName = popupView.findViewById(R.id.popup_channel_name);
            TextView tvResolution = popupView.findViewById(R.id.popup_resolution);
            TextView tvFps = popupView.findViewById(R.id.popup_fps);
            TextView tvAudio = popupView.findViewById(R.id.popup_audio);
            TextView tvIp = popupView.findViewById(R.id.popup_ip);
            TextView tvLine = popupView.findViewById(R.id.popup_line);
            ProgressBar progressBar = popupView.findViewById(R.id.popup_progress);
            TextView tvDuration = popupView.findViewById(R.id.popup_duration);
            TextView tvCurrentEpg = popupView.findViewById(R.id.popup_current_epg);
            TextView tvCurrentDesc = popupView.findViewById(R.id.popup_current_desc);
            TextView tvNextEpg = popupView.findViewById(R.id.popup_next_epg);
            TextView tvExtra = popupView.findViewById(R.id.popup_extra);
            TextView tvSpeed = popupView.findViewById(R.id.popup_speed);

            tvName.setText(currentChannel.name);
            String epgid = epgIdMap.get(currentChannel.name);
            String fileName = (epgid != null && !epgid.isEmpty()) ? epgid.replace("/", "_").replace("\\", "_") + ".png" : currentChannel.name.hashCode() + ".png";
            File logoFile = new File(logoDir, fileName);
            if (logoFile.exists()) {
                Bitmap bmp = BitmapFactory.decodeFile(logoFile.getAbsolutePath());
                if (bmp != null) {
                    ivLogo.setImageBitmap(bmp);
                    ivLogo.setVisibility(View.VISIBLE);
                } else {
                    ivLogo.setVisibility(View.GONE);
                }
            } else {
                ivLogo.setVisibility(View.GONE);
            }

            tvResolution.setText("FHD");
            tvFps.setText("29FPS");
            tvAudio.setText("立体声");
            tvIp.setText("IPV4");
            tvLine.setText("线路1/1");

            long now = System.currentTimeMillis();
            if (!currentEpgList.isEmpty()) {
                EPGParser.EpgProgram currentProg = currentEpgList.get(0);
                long start = currentProg.startTime;
                long end = currentProg.endTime;
                long total = end - start;
                long elapsed = now - start;
                if (elapsed < 0) elapsed = 0;
                if (elapsed > total) elapsed = total;
                int progress = (int) ((elapsed * 100) / total);
                progressBar.setProgress(progress);
                progressBar.setVisibility(View.VISIBLE);

                long remaining = end - now;
                if (remaining < 0) remaining = 0;
                long minutes = remaining / 60000;
                tvDuration.setText("距结束：" + minutes + "分钟");

                SimpleDateFormat sdf = new SimpleDateFormat("HH:mm", Locale.getDefault());
                String timeStr = sdf.format(new Date(start)) + "-" + sdf.format(new Date(end));
                String desc = (currentProg.desc != null && !currentProg.desc.isEmpty()) ? currentProg.desc : "暂无描述信息";
                tvCurrentEpg.setText("正在播放：" + timeStr + " " + currentProg.title);
                tvCurrentDesc.setText(desc);

                if (currentEpgList.size() > 1) {
                    EPGParser.EpgProgram next = currentEpgList.get(1);
                    String nextTime = sdf.format(new Date(next.startTime)) + "-" + sdf.format(new Date(next.endTime));
                    tvNextEpg.setText("下一节目：" + nextTime + " " + next.title);
                } else {
                    tvNextEpg.setText("下一节目：暂无");
                }
            } else {
                progressBar.setVisibility(View.GONE);
                tvDuration.setText("距结束：--");
                tvCurrentEpg.setText("正在播放：暂无EPG");
                tvCurrentDesc.setText("暂无描述信息");
                tvNextEpg.setText("下一节目：暂无");
            }

            boolean showSpeed = prefs.getBoolean(KEY_SHOW_SPEED, true);
            if (showSpeed) {
                // 获取实际网速（可通过 ExoPlayer 的带宽估计，这里简化）
                tvSpeed.setText("0.55MB/S");
                tvSpeed.setVisibility(View.VISIBLE);
            } else {
                tvSpeed.setVisibility(View.GONE);
            }

            tvExtra.setText("");

            PopupWindow popup = new PopupWindow(popupView,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    true);
            popup.setBackgroundDrawable(null);
            popup.setOutsideTouchable(true);
            popup.showAtLocation(findViewById(android.R.id.content), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0, -50);
            popupView.setOnClickListener(v -> popup.dismiss());
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "信息窗口异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void showLoadingDialog(String message) {
        if (progressDialog == null) {
            progressDialog = new ProgressDialog(this);
            progressDialog.setCancelable(false);
        }
        progressDialog.setMessage(message);
        progressDialog.show();
    }
    private void dismissLoadingDialog() {
        if (progressDialog != null && progressDialog.isShowing()) {
            progressDialog.dismiss();
        }
    }
    private void showNoSourceDialog() {
        dismissLoadingDialog();
        if (noSourceDialog != null && noSourceDialog.isShowing()) return;
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("提示");
        builder.setMessage("当前没有可用的订阅源，请先添加订阅源。");
        builder.setPositiveButton("去设置", (dialog, which) -> {
            Intent intent = new Intent(this, SettingsActivity.class);
            intent.putExtra("open_tab", 3);
            startActivity(intent);
        });
        builder.setNegativeButton("退出", (dialog, which) -> {
            finish();
        });
        builder.setCancelable(false);
        noSourceDialog = builder.create();
        noSourceDialog.show();
    }
    private void showLoadErrorDialog(String errorMsg) {
        dismissLoadingDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("加载失败");
        builder.setMessage("订阅源加载失败：\n" + errorMsg + "\n\n请检查网络或源地址是否正确。");
        builder.setPositiveButton("去设置", (dialog, which) -> {
            Intent intent = new Intent(this, SettingsActivity.class);
            intent.putExtra("open_tab", 3);
            startActivity(intent);
        });
        builder.setNegativeButton("重试", (dialog, which) -> {
            if (currentSubUrl != null && !currentSubUrl.isEmpty()) {
                showLoadingDialog("正在重试...");
                loadSourceForUrl(currentSubUrl);
            } else {
                showNoSourceDialog();
            }
        });
        builder.setCancelable(false);
        AlertDialog dialog = builder.create();
        dialog.show();
    }
    private void showFatalErrorDialog(String errorMsg) {
        dismissLoadingDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("严重错误");
        builder.setMessage("应用初始化失败：\n" + errorMsg + "\n\n请查看日志文件：\n" + LogUtils.getLogDir());
        builder.setPositiveButton("退出", (dialog, which) -> {
            finish();
        });
        builder.setCancelable(false);
        AlertDialog dialog = builder.create();
        dialog.show();
    }
    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_PERMISSIONS) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                LogUtils.writeLog("存储权限已获取");
                LogUtils.init(this);
                Toast.makeText(this, "日志目录: " + LogUtils.getLogDir(), Toast.LENGTH_SHORT).show();
            } else {
                LogUtils.writeLog("存储权限被拒绝");
                Toast.makeText(this, "存储权限被拒绝，日志可能无法保存", Toast.LENGTH_SHORT).show();
            }
        }
    }
    @Override
    protected void onResume() {
        super.onResume();
        loadSubscriptions();
        subAdapter.updateData(subEntryList);
        if (prefs.getBoolean(KEY_NEED_RELOAD, false)) {
            prefs.edit().remove(KEY_NEED_RELOAD).apply();
            selectedSubs = new HashSet<>(prefs.getStringSet(KEY_SELECTED_SUBS, new HashSet<>()));
            if (!selectedSubs.isEmpty()) {
                dismissNoSourceDialog();
                loadSelectedSources();
            } else {
                showNoSourceDialog();
            }
        } else {
            if (groupMap.isEmpty() && !subEntryList.isEmpty() && !isLoading) {
                if (!selectedSubs.isEmpty()) {
                    loadSelectedSources();
                }
            }
        }
    }
    private void loadSubscriptions() {
        subEntryList.clear();
        Set<String> subSet = prefs.getStringSet(KEY_SUB_LIST, new HashSet<>());
        if (subSet != null) {
            for (String entry : subSet) {
                String[] parts = entry.split("\\|\\|");
                if (parts.length >= 2) {
                    SubEntry se = new SubEntry();
                    se.name = parts[0];
                    se.url = parts[1];
                    subEntryList.add(se);
                }
            }
        }
        SubEntry fav = new SubEntry();
        fav.name = "我的收藏";
        fav.url = null;
        subEntryList.add(0, fav);
    }
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (isScheduleMode) {
                toggleScheduleMode();
                return true;
            }
            if (isOverlayVisible) {
                hideOverlay();
                return true;
            }
            startActivity(new Intent(this, SettingsActivity.class));
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) {
            player.release();
            player = null;
        }
        mainHandler.removeCallbacks(hideOverlayRunnable);
        dismissLoadingDialog();
        logoDownloadExecutor.shutdownNow();
        LogUtils.writeLog("=== 应用退出 ===");
    }

    // ---------- Adapters ----------
    static class SubAdapter extends RecyclerView.Adapter<SubAdapter.ViewHolder> {
        private List<SubEntry> data;
        private Set<String> selectedSubs;
        private OnSubClickListener listener;
        interface OnSubClickListener { void onClick(SubEntry entry); }
        SubAdapter(List<SubEntry> data, Set<String> selectedSubs, OnSubClickListener listener) {
            this.data = data;
            this.selectedSubs = selectedSubs;
            this.listener = listener;
        }
        void updateData(List<SubEntry> newData) { this.data = newData; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_sub, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SubEntry entry = data.get(position);
            String key = entry.name + "||" + entry.url;
            boolean isSelected = selectedSubs.contains(key);
            holder.name.setText(entry.name);
            if ("我的收藏".equals(entry.name)) {
                holder.name.setTextColor(0xFFFFD700);
            } else {
                holder.name.setTextColor(isSelected ? 0xFF4CAF50 : 0xFFFFFFFF);
            }
            holder.itemView.setOnClickListener(v -> listener.onClick(entry));
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.sub_name); }
        }
    }
    static class GroupAdapter extends RecyclerView.Adapter<GroupAdapter.ViewHolder> {
        private List<String> data;
        private String selectedGroup;
        private OnGroupClickListener listener;
        interface OnGroupClickListener { void onClick(String group); }
        GroupAdapter(List<String> data, OnGroupClickListener listener) { this.data = data; this.listener = listener; }
        void updateData(List<String> newData) { this.data = newData; notifyDataSetChanged(); }
        void setSelectedGroup(String group) { this.selectedGroup = group; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_group, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            String group = data.get(position);
            holder.name.setText(group);
            holder.itemView.setBackgroundColor(group.equals(selectedGroup) ? 0x3300A0FF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(group));
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.group_name); }
        }
    }
    static class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private SourceManager.Channel selectedChannel;
        private OnChannelClickListener listener;
        private OnFavoriteClickListener favListener;
        private Set<String> favoriteSet;
        private File logoDir;
        private MainActivity activity;
        private Map<String, List<EPGParser.EpgProgram>> epgCache;
        interface OnChannelClickListener { void onClick(SourceManager.Channel channel); }
        interface OnFavoriteClickListener { void onFavorite(SourceManager.Channel channel); }
        ChannelAdapter(List<SourceManager.Channel> data, Set<String> favorites, File logoDir,
                       OnChannelClickListener listener, OnFavoriteClickListener favListener,
                       MainActivity activity, Map<String, List<EPGParser.EpgProgram>> epgCache) {
            this.data = data; this.favoriteSet = favorites; this.logoDir = logoDir;
            this.listener = listener; this.favListener = favListener;
            this.activity = activity;
            this.epgCache = epgCache;
        }
        void updateData(List<SourceManager.Channel> newData) { this.data = newData; notifyDataSetChanged(); }
        void updateFavorites(Set<String> newFavorites) { this.favoriteSet = newFavorites; notifyDataSetChanged(); }
        void setSelectedChannel(SourceManager.Channel ch) { this.selectedChannel = ch; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_channel, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SourceManager.Channel ch = data.get(position);
            holder.name.setText(ch.name);
            boolean isFav = favoriteSet.contains(ch.name);
            holder.favIcon.setVisibility(isFav ? View.VISIBLE : View.GONE);
            holder.itemView.setBackgroundColor(ch.equals(selectedChannel) ? 0x3300A0FF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(ch));
            holder.itemView.setOnLongClickListener(v -> { favListener.onFavorite(ch); return true; });
            String epgid = activity.epgIdMap.get(ch.name);
            String fileName = (epgid != null && !epgid.isEmpty()) ? epgid.replace("/", "_").replace("\\", "_") + ".png" : ch.name.hashCode() + ".png";
            File logoFile = new File(logoDir, fileName);
            if (logoFile.exists()) {
                Bitmap bmp = BitmapFactory.decodeFile(logoFile.getAbsolutePath());
                if (bmp != null) {
                    holder.logo.setImageBitmap(bmp);
                    holder.logo.setVisibility(View.VISIBLE);
                    holder.textLogo.setVisibility(View.GONE);
                } else {
                    holder.logo.setVisibility(View.GONE);
                    holder.textLogo.setVisibility(View.VISIBLE);
                    holder.textLogo.setText(ch.name.substring(0, 1));
                }
            } else {
                holder.logo.setVisibility(View.GONE);
                holder.textLogo.setVisibility(View.VISIBLE);
                holder.textLogo.setText(ch.name.substring(0, 1));
                if (ch.logoUrl != null && !ch.logoUrl.isEmpty() || activity.epgIconMap.containsKey(ch.name)) {
                    activity.processChannelLogo(ch);
                }
            }
            String currentTitle = null;
            if (epgCache != null && epgCache.containsKey(ch.name)) {
                List<EPGParser.EpgProgram> epgList = epgCache.get(ch.name);
                if (epgList != null && !epgList.isEmpty()) {
                    long now = System.currentTimeMillis();
                    for (EPGParser.EpgProgram prog : epgList) {
                        if (prog.startTime <= now && prog.endTime > now) {
                            currentTitle = prog.title;
                            break;
                        }
                    }
                    if (currentTitle == null && !epgList.isEmpty()) {
                        for (EPGParser.EpgProgram prog : epgList) {
                            if (prog.startTime > now) {
                                currentTitle = "即将播出：" + prog.title;
                                break;
                            }
                        }
                    }
                }
            }
            if (currentTitle != null && !currentTitle.isEmpty()) {
                holder.epgTitle.setText(currentTitle);
                holder.epgTitle.setVisibility(View.VISIBLE);
            } else {
                holder.epgTitle.setVisibility(View.GONE);
            }
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name, favIcon, epgTitle, textLogo;
            ImageView logo;
            ViewHolder(View v) { super(v);
                name = v.findViewById(R.id.channel_name);
                favIcon = v.findViewById(R.id.channel_fav);
                logo = v.findViewById(R.id.channel_logo);
                textLogo = v.findViewById(R.id.text_logo);
                epgTitle = v.findViewById(R.id.channel_epg_title);
            }
        }
    }
    static class ScheduleChannelAdapter extends RecyclerView.Adapter<ScheduleChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private Set<String> favoriteSet;
        private File logoDir;
        private OnChannelClickListener listener;
        private MainActivity activity;
        interface OnChannelClickListener { void onClick(SourceManager.Channel channel); }
        ScheduleChannelAdapter(List<SourceManager.Channel> data, Set<String> favorites, File logoDir, MainActivity activity, OnChannelClickListener listener) {
            this.data = data;
            this.favoriteSet = favorites;
            this.logoDir = logoDir;
            this.activity = activity;
            this.listener = listener;
        }
        void updateData(List<SourceManager.Channel> newData) { this.data = newData; notifyDataSetChanged(); }
        void updateFavorites(Set<String> newFavorites) { this.favoriteSet = newFavorites; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_channel, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SourceManager.Channel ch = data.get(position);
            holder.name.setText(ch.name);
            boolean isFav = favoriteSet.contains(ch.name);
            holder.favIcon.setVisibility(isFav ? View.VISIBLE : View.GONE);
            if (activity != null) {
                String epgid = activity.epgIdMap.get(ch.name);
                String fileName = (epgid != null && !epgid.isEmpty()) ? epgid.replace("/", "_").replace("\\", "_") + ".png" : ch.name.hashCode() + ".png";
                File logoFile = new File(logoDir, fileName);
                if (logoFile.exists()) {
                    Bitmap bmp = BitmapFactory.decodeFile(logoFile.getAbsolutePath());
                    if (bmp != null) {
                        holder.logo.setImageBitmap(bmp);
                        holder.logo.setVisibility(View.VISIBLE);
                        holder.textLogo.setVisibility(View.GONE);
                    } else {
                        holder.logo.setVisibility(View.GONE);
                        holder.textLogo.setVisibility(View.VISIBLE);
                        holder.textLogo.setText(ch.name.substring(0, 1));
                    }
                } else {
                    holder.logo.setVisibility(View.GONE);
                    holder.textLogo.setVisibility(View.VISIBLE);
                    holder.textLogo.setText(ch.name.substring(0, 1));
                    if (ch.logoUrl != null && !ch.logoUrl.isEmpty() || activity.epgIconMap.containsKey(ch.name)) {
                        activity.processChannelLogo(ch);
                    }
                }
            } else {
                holder.logo.setVisibility(View.GONE);
                holder.textLogo.setVisibility(View.VISIBLE);
                holder.textLogo.setText(ch.name.substring(0, 1));
            }
            holder.itemView.setOnClickListener(v -> listener.onClick(ch));
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name, favIcon, textLogo;
            ImageView logo;
            ViewHolder(View v) { super(v);
                name = v.findViewById(R.id.channel_name);
                favIcon = v.findViewById(R.id.channel_fav);
                logo = v.findViewById(R.id.channel_logo);
                textLogo = v.findViewById(R.id.text_logo);
            }
        }
    }
    static class ScheduleEpgAdapter extends RecyclerView.Adapter<ScheduleEpgAdapter.ViewHolder> {
        private List<EPGParser.EpgProgram> data = new ArrayList<>();
        private long currentTime;
        ScheduleEpgAdapter(List<EPGParser.EpgProgram> data) { this.data = data; }
        void setItems(List<EPGParser.EpgProgram> newData, long currentTime) {
            this.data = newData;
            this.currentTime = currentTime;
            notifyDataSetChanged();
        }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_epg, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            EPGParser.EpgProgram prog = data.get(position);
            SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.getDefault());
            String time = timeFormat.format(new Date(prog.startTime)) + "-" + timeFormat.format(new Date(prog.endTime));
            holder.time.setText(time);
            holder.title.setText(prog.title);
            if (prog.startTime <= currentTime && prog.endTime > currentTime) {
                holder.itemView.setBackgroundColor(0x3300A0FF);
                holder.title.setTextColor(0xFFFFD700);
                holder.time.setTextColor(0xFFFFD700);
            } else {
                holder.itemView.setBackgroundColor(0x00000000);
                holder.title.setTextColor(0xFFFFFFFF);
                holder.time.setTextColor(0xAAAAAA);
            }
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView time, title;
            ViewHolder(View v) { super(v); time = v.findViewById(R.id.epg_time); title = v.findViewById(R.id.epg_title); }
        }
    }
}
MAIN

# ---------- SettingsActivity.java（完整） ----------
cat > "$TEMPLATE_DIR/src/SettingsActivity.java" <<'SETTINGS'
package com.whyun.witv;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import com.whyun.witv.player.PlayerConfigManager;
public class SettingsActivity extends AppCompatActivity {
    private RecyclerView menuRecycler, contentRecycler;
    private MenuAdapter menuAdapter;
    private ContentAdapter contentAdapter;
    private String[] menuTitles = {"线路选择", "频道搜索", "播放设置", "列表订阅", "EPG订阅", "分类管理", "订阅管理", "显示设置", "偏好设置", "列表设置", "其他设置", "推送频道", "更多管理"};
    private int currentPos = 0;
    private SharedPreferences prefs;
    private static final String KEY_SUB_LIST = "sub_list";
    private static final String KEY_SELECTED_SUBS = "selected_subs";
    private static final String KEY_AUTO_RECONNECT = "auto_reconnect";
    private static final String KEY_NEED_RELOAD = "need_reload";
    private static final String KEY_SHOW_SPEED = "show_speed";
    private String localIp = "";
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        localIp = getLocalIpAddress();
        menuRecycler = findViewById(R.id.menu_recycler);
        contentRecycler = findViewById(R.id.content_recycler);
        menuRecycler.setLayoutManager(new LinearLayoutManager(this));
        menuAdapter = new MenuAdapter(menuTitles, pos -> {
            currentPos = pos;
            menuAdapter.setSelected(pos);
            showContent(pos);
        });
        menuRecycler.setAdapter(menuAdapter);
        contentRecycler.setLayoutManager(new LinearLayoutManager(this));
        contentAdapter = new ContentAdapter();
        contentRecycler.setAdapter(contentAdapter);
        int openTab = getIntent().getIntExtra("open_tab", -1);
        if (openTab >= 0 && openTab < menuTitles.length) {
            currentPos = openTab;
            menuAdapter.setSelected(openTab);
            showContent(openTab);
        } else {
            menuAdapter.setSelected(0);
            showContent(0);
        }
    }
    private String getLocalIpAddress() {
        try {
            for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements();) {
                NetworkInterface intf = en.nextElement();
                for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements();) {
                    InetAddress inetAddress = enumIpAddr.nextElement();
                    if (!inetAddress.isLoopbackAddress() && inetAddress.getHostAddress().indexOf(':') == -1) {
                        return inetAddress.getHostAddress();
                    }
                }
            }
        } catch (Exception e) {}
        return "127.0.0.1";
    }
    private void showContent(int pos) {
        List<ContentItem> items = new ArrayList<>();
        switch (pos) {
            case 0: items.add(new ContentItem("线路选择", "点击选择", v -> showLineSelection())); break;
            case 1: items.add(new ContentItem("频道搜索", "点击搜索", v -> Toast.makeText(this, "频道搜索功能", Toast.LENGTH_SHORT).show())); break;
            case 2: buildPlaySettings(items); break;
            case 3: buildSubscriptionList(items); break;
            case 4: buildEpgSubscriptionList(items); break;
            case 5: items.add(new ContentItem("分类管理", "管理", v -> Toast.makeText(this, "分类管理", Toast.LENGTH_SHORT).show())); break;
            case 6: items.add(new ContentItem("订阅管理", "管理", v -> Toast.makeText(this, "订阅管理", Toast.LENGTH_SHORT).show())); break;
            case 7: buildDisplaySettings(items); break;
            case 8: items.add(new ContentItem("偏好设置", "点击", v -> showPreferenceSettings())); break;
            case 9: items.add(new ContentItem("列表设置", "点击", v -> showListSettings())); break;
            case 10: items.add(new ContentItem("其他设置", "点击", v -> showOtherSettings())); break;
            case 11: items.add(new ContentItem("推送频道", "推送", v -> Toast.makeText(this, "推送频道", Toast.LENGTH_SHORT).show())); break;
            case 12: items.add(new ContentItem("更多管理", "查看", v -> showMoreInfo())); break;
        }
        contentAdapter.setItems(items);
    }
    private void buildPlaySettings(List<ContentItem> items) {
        items.add(new ContentItem("解码方式", "点击设置", v -> showDecoderDialog()));
        items.add(new ContentItem("画面比例", "点击设置", v -> showAspectDialog()));
        items.add(new ContentItem("超时换源", "点击设置", v -> Toast.makeText(this, "超时换源功能", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("断线重连", "点击切换", v -> toggleAutoReconnect()));
    }
    private void toggleAutoReconnect() {
        boolean current = prefs.getBoolean(KEY_AUTO_RECONNECT, true);
        boolean newVal = !current;
        prefs.edit().putBoolean(KEY_AUTO_RECONNECT, newVal).apply();
        Toast.makeText(this, "断线重连已" + (newVal ? "开启" : "关闭"), Toast.LENGTH_SHORT).show();
        showContent(2);
    }
    private void buildSubscriptionList(List<ContentItem> items) {
        items.add(new ContentItem("扫码输入", "点击二维码查看说明", v -> Toast.makeText(this, "IP: " + localIp + " 端口 9978", Toast.LENGTH_LONG).show()));
        items.add(new ContentItem("列表订阅", "http://" + localIp + ":9978/", v -> {}));
        Set<String> subSet = prefs.getStringSet(KEY_SUB_LIST, new HashSet<>());
        Set<String> selectedSet = new HashSet<>(prefs.getStringSet(KEY_SELECTED_SUBS, new HashSet<>()));
        if (subSet != null && !subSet.isEmpty()) {
            for (String entry : subSet) {
                String[] parts = entry.split("\\|\\|");
                String name = parts.length > 0 ? parts[0] : entry;
                String url = parts.length > 1 ? parts[1] : "";
                boolean isSelected = selectedSet.contains(entry);
                items.add(new ContentItem(name, url, isSelected, v -> {
                    Set<String> currentSelected = new HashSet<>(prefs.getStringSet(KEY_SELECTED_SUBS, new HashSet<>()));
                    if (currentSelected.contains(entry)) {
                        currentSelected.remove(entry);
                    } else {
                        currentSelected.add(entry);
                    }
                    prefs.edit().putStringSet(KEY_SELECTED_SUBS, currentSelected).apply();
                    prefs.edit().putBoolean(KEY_NEED_RELOAD, true).apply();
                    Toast.makeText(this, currentSelected.contains(entry) ? "已选中" : "已取消选中", Toast.LENGTH_SHORT).show();
                    showContent(3);
                }));
            }
        }
        items.add(new ContentItem("+ 添加订阅", "", v -> showAddSubscriptionDialog()));
    }
    private void buildEpgSubscriptionList(List<ContentItem> items) {
        items.add(new ContentItem("扫码输入", "点击二维码查看说明", v -> Toast.makeText(this, "EPG二维码功能", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("EPG订阅", "http://" + localIp + ":9978/", v -> {}));
        String epgUrl = prefs.getString("epg_url", "");
        if (!epgUrl.isEmpty()) {
            items.add(new ContentItem("当前EPG", epgUrl, true, v -> {}));
        }
        items.add(new ContentItem("缓存", "每天8点", v -> Toast.makeText(this, "缓存设置", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("[XML]epw", "", v -> {}));
        items.add(new ContentItem("+ 添加EPG", "", v -> showEpgDialog()));
    }
    private void buildDisplaySettings(List<ContentItem> items) {
        boolean showSpeed = prefs.getBoolean(KEY_SHOW_SPEED, true);
        items.add(new ContentItem("显示网速", showSpeed ? "开启" : "关闭", v -> {
            boolean current = prefs.getBoolean(KEY_SHOW_SPEED, true);
            prefs.edit().putBoolean(KEY_SHOW_SPEED, !current).apply();
            Toast.makeText(this, "网速显示已" + (!current ? "开启" : "关闭"), Toast.LENGTH_SHORT).show();
            showContent(7);
        }));
        items.add(new ContentItem("显示时间", "开启", v -> Toast.makeText(this, "功能待完善", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("隐藏频道图标", "关闭", v -> Toast.makeText(this, "功能待完善", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("隐藏底部图标", "关闭", v -> Toast.makeText(this, "功能待完善", Toast.LENGTH_SHORT).show()));
    }
    private void showAddSubscriptionDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("添加列表订阅");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(50,20,50,20);
        final EditText nameInput = new EditText(this);
        nameInput.setHint("名称（选填）");
        layout.addView(nameInput);
        final EditText urlInput = new EditText(this);
        urlInput.setHint("地址（必填）");
        layout.addView(urlInput);
        builder.setView(layout);
        builder.setPositiveButton("确定", null);
        builder.setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String name = nameInput.getText().toString().trim();
            String url = urlInput.getText().toString().trim();
            if (url.isEmpty()) { Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show(); return; }
            if (name.isEmpty()) name = url;
            String entry = name + "||" + url;
            Set<String> subSet = new HashSet<>(prefs.getStringSet(KEY_SUB_LIST, new HashSet<>()));
            subSet.add(entry);
            prefs.edit().putStringSet(KEY_SUB_LIST, subSet).apply();
            Set<String> selectedSet = new HashSet<>(prefs.getStringSet(KEY_SELECTED_SUBS, new HashSet<>()));
            selectedSet.add(entry);
            prefs.edit().putStringSet(KEY_SELECTED_SUBS, selectedSet).apply();
            prefs.edit().putBoolean(KEY_NEED_RELOAD, true).apply();
            Toast.makeText(this, "订阅已添加并选中", Toast.LENGTH_SHORT).show();
            showContent(3);
            finish();
            dialog.dismiss();
        });
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> dialog.dismiss());
    }
    private void showEpgDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("EPG订阅");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(50,20,50,20);
        final EditText urlInput = new EditText(this);
        urlInput.setHint("EPG地址（XMLTV格式）");
        layout.addView(urlInput);
        builder.setView(layout);
        builder.setPositiveButton("确定", null);
        builder.setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String url = urlInput.getText().toString().trim();
            if (url.isEmpty()) { Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show(); return; }
            prefs.edit().putString("epg_url", url).apply();
            Toast.makeText(this, "EPG地址已保存", Toast.LENGTH_SHORT).show();
            showContent(4);
            dialog.dismiss();
        });
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> dialog.dismiss());
    }
    private void showLineSelection() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("线路选择").setItems(new String[]{"源1","源2","源3"}, (d,w) -> Toast.makeText(this, "选择线路"+(w+1), Toast.LENGTH_SHORT).show());
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showDecoderDialog() {
        final String[] decoders = {"系统解码", "IJK硬解", "IJK软解", "EXO硬解", "EXO软解", "MPV硬解", "MPV软解", "自动"};
        int current = PlayerConfigManager.getDecoder();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("解码方式")
                .setSingleChoiceItems(decoders, current, (d, which) -> {
                    PlayerConfigManager.setDecoder(which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showAspectDialog() {
        final String[] aspects = {"默认", "16:9", "4:3", "填充", "原始", "裁剪", "电影"};
        int current = 0;
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("画面比例")
                .setSingleChoiceItems(aspects, current, (d, which) -> {
                    PlayerConfigManager.setAspectRatio(aspects[which]);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showPreferenceSettings() {
        final String[] items = {"记忆解码", "换台反转", "跨选分组", "关闭密码"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("偏好设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showListSettings() {
        final String[] items = {"全局字体大小", "列表宽度", "底部信息栏宽度"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("列表设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showOtherSettings() {
        final String[] items = {"EPG缓存"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("其他设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showMoreInfo() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("更多管理").setMessage("witv 1.0.0\n软件仅供测试").setPositiveButton("确定", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    static class ContentItem {
        String title, subtitle; boolean isSelected; View.OnClickListener listener;
        ContentItem(String t, String s, View.OnClickListener l) { title=t; subtitle=s; isSelected=false; listener=l; }
        ContentItem(String t, String s, boolean sel, View.OnClickListener l) { title=t; subtitle=s; isSelected=sel; listener=l; }
    }
    static class MenuAdapter extends RecyclerView.Adapter<MenuAdapter.ViewHolder> {
        private String[] titles; private OnMenuClickListener listener; private int selected=-1;
        interface OnMenuClickListener { void onClick(int pos); }
        MenuAdapter(String[] t, OnMenuClickListener l) { titles=t; listener=l; }
        void setSelected(int pos) { selected=pos; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_menu, parent, false);
            return new ViewHolder(v);
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            holder.text.setText(titles[position]);
            holder.itemView.setBackgroundColor(selected==position ? 0x33FFFFFF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(position));
        }
        @Override public int getItemCount() { return titles.length; }
        static class ViewHolder extends RecyclerView.ViewHolder { TextView text; ViewHolder(View v) { super(v); text=v.findViewById(R.id.menu_text); } }
    }
    static class ContentAdapter extends RecyclerView.Adapter<ContentAdapter.ViewHolder> {
        private List<ContentItem> items = new ArrayList<>();
        void setItems(List<ContentItem> list) { items=list; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_content, parent, false);
            return new ViewHolder(v);
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            ContentItem item = items.get(position);
            holder.title.setText(item.title);
            holder.subtitle.setText(item.subtitle);
            if (item.isSelected) {
                holder.title.setTextColor(Color.BLUE);
                holder.check.setVisibility(View.VISIBLE);
            } else {
                holder.title.setTextColor(Color.WHITE);
                holder.check.setVisibility(View.GONE);
            }
            holder.itemView.setOnClickListener(item.listener);
        }
        @Override public int getItemCount() { return items.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView title, subtitle, check;
            ViewHolder(View v) { super(v); title=v.findViewById(R.id.content_title); subtitle=v.findViewById(R.id.content_subtitle); check=v.findViewById(R.id.content_check); }
        }
    }
}
SETTINGS

# ==================== 布局文件 ====================
mkdir -p "$TEMPLATE_DIR/res/layout"
cat > "$TEMPLATE_DIR/res/layout/activity_main.xml" <<'LAYOUT1'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">
    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />
    <View
        android:id="@+id/left_click_area"
        android:layout_width="40dp"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        android:background="#00000000"
        android:clickable="true"
        android:focusable="true" />
    <LinearLayout
        android:id="@+id/overlay_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="horizontal"
        android:background="#00000000"
        android:visibility="gone">
        <FrameLayout
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.5">
            <LinearLayout
                android:id="@+id/overlay_layout"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:orientation="horizontal"
                android:background="#CC000000"
                android:visibility="visible">
                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0.2"
                    android:orientation="vertical"
                    android:background="#33000000"
                    android:padding="2dp">
                    <TextView
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:text="订阅源"
                        android:textColor="#FFFFFF"
                        android:textSize="11sp"
                        android:paddingBottom="2dp" />
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/sub_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="0dp"
                        android:layout_weight="1" />
                </LinearLayout>
                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0.2"
                    android:orientation="vertical"
                    android:background="#44000000"
                    android:padding="2dp">
                    <TextView
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:text="分组"
                        android:textColor="#FFFFFF"
                        android:textSize="11sp"
                        android:paddingBottom="2dp" />
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/group_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="0dp"
                        android:layout_weight="1" />
                </LinearLayout>
                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0.6"
                    android:orientation="vertical"
                    android:background="#55000000"
                    android:padding="2dp">
                    <LinearLayout
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:gravity="center_vertical">
                        <TextView
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="频道列表"
                            android:textColor="#FFFFFF"
                            android:textSize="11sp" />
                        <Button
                            android:id="@+id/btn_epg_schedule"
                            android:layout_width="wrap_content"
                            android:layout_height="wrap_content"
                            android:text="节目单"
                            android:textColor="#FFD700"
                            android:background="@null"
                            android:textSize="11sp" />
                    </LinearLayout>
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/channel_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="0dp"
                        android:layout_weight="1" />
                </LinearLayout>
            </LinearLayout>
            <LinearLayout
                android:id="@+id/schedule_layout"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:orientation="horizontal"
                android:background="#CC000000"
                android:visibility="gone">
                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0.4"
                    android:orientation="vertical"
                    android:background="#55000000"
                    android:padding="2dp">
                    <TextView
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:text="频道列表"
                        android:textColor="#FFFFFF"
                        android:textSize="11sp" />
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/schedule_channel_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="0dp"
                        android:layout_weight="1" />
                </LinearLayout>
                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0.6"
                    android:orientation="vertical"
                    android:background="#66000000"
                    android:padding="2dp">
                    <LinearLayout
                        android:id="@+id/day_tabs"
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:gravity="center"
                        android:padding="4dp" />
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/schedule_epg_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="0dp"
                        android:layout_weight="1" />
                </LinearLayout>
                <View
                    android:id="@+id/schedule_close_area"
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="0"
                    android:background="#00000000"
                    android:clickable="true" />
            </LinearLayout>
        </FrameLayout>
        <View
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.5" />
    </LinearLayout>
</FrameLayout>
LAYOUT1

cat > "$TEMPLATE_DIR/res/layout/item_channel.xml" <<'LAYOUT2'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="2dp"
    android:background="?attr/selectableItemBackground">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <FrameLayout
            android:layout_width="24dp"
            android:layout_height="24dp">
            <ImageView
                android:id="@+id/channel_logo"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitCenter"
                android:visibility="gone" />
            <TextView
                android:id="@+id/text_logo"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="14sp"
                android:textColor="#FFFFFF"
                android:background="#333333"
                android:visibility="gone" />
        </FrameLayout>
        <TextView
            android:id="@+id/channel_name"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:textSize="13sp"
            android:textColor="#FFFFFF"
            android:paddingStart="4dp" />
        <TextView
            android:id="@+id/channel_fav"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="★"
            android:textSize="14sp"
            android:textColor="#FFD700"
            android:visibility="gone" />
    </LinearLayout>
    <TextView
        android:id="@+id/channel_epg_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="10sp"
        android:textColor="#AAAAAA"
        android:paddingStart="28dp"
        android:visibility="gone" />
</LinearLayout>
LAYOUT2

cat > "$TEMPLATE_DIR/res/layout/popup_info.xml" <<'LAYOUT3'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:background="#CC000000"
    android:paddingLeft="14dp"
    android:paddingRight="14dp"
    android:paddingTop="10dp"
    android:paddingBottom="10dp"
    android:layout_marginLeft="20dp"
    android:layout_marginRight="20dp">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="4dp">
        <ImageView
            android:id="@+id/popup_logo"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:scaleType="fitCenter"
            android:visibility="gone" />
        <TextView
            android:id="@+id/popup_channel_name"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:text="频道名"
            android:textColor="#FFFFFF"
            android:textSize="18sp"
            android:textStyle="bold" />
    </LinearLayout>
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="2dp">
        <TextView
            android:id="@+id/popup_resolution"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="FHD"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" "
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_fps"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="29FPS"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" "
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_audio"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="立体声"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" "
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_ip"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="IPV4"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" "
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_line"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="线路1/1"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
    </LinearLayout>
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="2dp">
        <ProgressBar
            android:id="@+id/popup_progress"
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="0dp"
            android:layout_height="6dp"
            android:layout_weight="1"
            android:progressTint="#FFD700"
            android:progressBackgroundTint="#444444"
            android:visibility="gone" />
        <TextView
            android:id="@+id/popup_duration"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:text="距结束：56分钟"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
    </LinearLayout>
    <TextView
        android:id="@+id/popup_current_epg"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="正在播放：22:32-23:34职场健康课"
        android:textColor="#FFFFFF"
        android:textSize="14sp"
        android:layout_marginBottom="2dp"
        android:textStyle="bold" />
    <TextView
        android:id="@+id/popup_current_desc"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="的负担"
        android:textColor="#CCCCCC"
        android:textSize="12sp"
        android:layout_marginBottom="6dp"
        android:maxLines="4"
        android:ellipsize="end" />
    <TextView
        android:id="@+id/popup_next_epg"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="下一节目：23:34-23:59经济半小时"
        android:textColor="#FFFFFF"
        android:textSize="13sp"
        android:textStyle="bold" />
    <TextView
        android:id="@+id/popup_extra"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text=""
        android:textColor="#888888"
        android:textSize="11sp"
        android:layout_marginTop="4dp" />
    <TextView
        android:id="@+id/popup_speed"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="0.55MB/S"
        android:textColor="#AAAAAA"
        android:textSize="11sp"
        android:gravity="end"
        android:visibility="gone" />
</LinearLayout>
LAYOUT3

cat > "$TEMPLATE_DIR/res/layout/item_sub.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/sub_name"
    android:layout_width="match_parent"
    android:layout_height="40dp"
    android:gravity="center_vertical"
    android:paddingLeft="6dp"
    android:textSize="12sp"
    android:textColor="#FFFFFF"
    android:background="?attr/selectableItemBackground" />
EOF
cat > "$TEMPLATE_DIR/res/layout/item_group.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/group_name"
    android:layout_width="match_parent"
    android:layout_height="40dp"
    android:gravity="center_vertical"
    android:paddingLeft="6dp"
    android:textSize="12sp"
    android:textColor="#FFFFFF"
    android:background="?attr/selectableItemBackground" />
EOF
cat > "$TEMPLATE_DIR/res/layout/item_epg.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="2dp"
    android:background="?attr/selectableItemBackground">
    <TextView
        android:id="@+id/epg_time"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="11sp"
        android:textColor="#AAAAAA"
        android:minWidth="70dp" />
    <TextView
        android:id="@+id/epg_title"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textSize="12sp"
        android:textColor="#FFFFFF"
        android:paddingStart="6dp" />
</LinearLayout>
EOF
cat > "$TEMPLATE_DIR/res/layout/activity_settings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="horizontal" android:background="#DD000000">
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/menu_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:background="#33000000" android:padding="4dp" />
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/content_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="2" android:background="#44000000" android:padding="4dp" />
</LinearLayout>
EOF
cat > "$TEMPLATE_DIR/res/layout/item_menu.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/menu_text"
    android:layout_width="match_parent"
    android:layout_height="36dp"
    android:gravity="center_vertical"
    android:paddingLeft="8dp"
    android:textSize="13sp"
    android:textColor="#FFFFFF"
    android:background="#33000000" />
EOF
cat > "$TEMPLATE_DIR/res/layout/item_content.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="6dp"
    android:background="#22000000">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">
        <TextView
            android:id="@+id/content_title"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:textSize="13sp"
            android:textColor="#FFFFFF" />
        <TextView
            android:id="@+id/content_check"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="√"
            android:textSize="14sp"
            android:textColor="#4CAF50"
            android:visibility="gone" />
    </LinearLayout>
    <TextView
        android:id="@+id/content_subtitle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="10sp"
        android:textColor="#AAAAAA" />
</LinearLayout>
EOF

# ==================== 图标资源 ====================
mkdir -p "$TEMPLATE_DIR/res/drawable"
cat > "$TEMPLATE_DIR/res/drawable/ic_launcher.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp" android:height="48dp" android:viewportWidth="24" android:viewportHeight="24">
  <path android:fillColor="#FF5722" android:pathData="M8,5v14l11,-7z"/>
</vector>
EOF
cat > "$TEMPLATE_DIR/res/drawable/ic_settings.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94s-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z"/>
</vector>
EOF
cat > "$TEMPLATE_DIR/res/drawable/ic_epg.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19 3h-1V1h-2v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7z"/>
</vector>
EOF
cat > "$TEMPLATE_DIR/res/drawable/ic_announce.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
</vector>
EOF

echo "✅ 模板生成完毕"

# ==================== 复制模板到项目 ====================
echo "📂 复制模板文件到项目..."
rm -rf app/src/main/java/com/whyun/witv/ui
rm -f app/src/main/java/com/whyun/witv/SettingsActivity.java
rm -rf app/build
cp -r "$TEMPLATE_DIR/src/." app/src/main/java/com/whyun/witv/
cp -r "$TEMPLATE_DIR/res/." app/src/main/res/
cp "$TEMPLATE_DIR/configuration.json" app/src/main/assets/
cp "$TEMPLATE_DIR/assets/epg_data.json" app/src/main/assets/
mkdir -p app/src/main/assets/localData app/src/main/assets/backup app/src/main/assets/download \
         app/src/main/assets/videoFile app/src/main/assets/configuration app/src/main/assets/logo \
         app/src/main/assets/js app/src/main/assets/py app/src/main/assets/webviewJscode app/src/main/assets/epgCache
echo "✅ 文件复制完成"

# ==================== 自定义图标 ====================
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

# ==================== 修改 build.gradle 添加签名配置 ====================
APP_GRADLE="app/build.gradle"
cp "$APP_GRADLE" "$APP_GRADLE.bak"
if ! grep -q "signingConfigs" "$APP_GRADLE"; then
    sed -i '/android {/a \    signingConfigs {\n        release {\n            storeFile file("'"$KEYSTORE_FILE"'")\n            storePassword "'"$KEYSTORE_PASS"'"\n            keyAlias "'"$KEY_ALIAS"'"\n            keyPassword "'"$KEY_PASS"'"\n        }\n    }' "$APP_GRADLE"
fi
sed -i '/buildTypes {/a \        debug {\n            signingConfig signingConfigs.release\n        }\n        release {\n            signingConfig signingConfigs.release\n        }' "$APP_GRADLE"
echo "✅ 签名配置已添加"

# ==================== 添加依赖 ====================
sed -i '/implementation.*exoplayer/d' "$APP_GRADLE"
sed -i '/implementation.*okhttp/d' "$APP_GRADLE"
sed -i '/implementation.*gson/d' "$APP_GRADLE"
sed -i '/implementation.*preference/d' "$APP_GRADLE"
sed -i '/dependencies {/a \    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
echo "✅ 依赖已添加"

# ==================== 修改 AndroidManifest.xml 横屏和权限 ====================
MANIFEST="app/src/main/AndroidManifest.xml"
cp "$MANIFEST" "$MANIFEST.bak"
cat > /tmp/fix_manifest.py <<'PYEOF'
import sys, xml.etree.ElementTree as ET
from xml.dom import minidom
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
manifest_file = "app/src/main/AndroidManifest.xml"
pkg = "com.whyun.witv"
try:
    tree = ET.parse(manifest_file); root = tree.getroot()
except Exception as e:
    print(f"解析失败: {e}", file=sys.stderr); sys.exit(1)
app = root.find('application')
if app is None:
    print("未找到 application", file=sys.stderr); sys.exit(1)
icon_attr = '{http://schemas.android.com/apk/res/android}icon'
app.set(icon_attr, '@drawable/ic_launcher')
for act in app.findall('activity'): app.remove(act)
main_act = ET.Element('activity')
main_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.MainActivity")
main_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
main_act.set('{http://schemas.android.com/apk/res/android}screenOrientation', 'landscape')
intent_filter = ET.SubElement(main_act, 'intent-filter')
action = ET.SubElement(intent_filter, 'action')
action.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.action.MAIN')
cat = ET.SubElement(intent_filter, 'category')
cat.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.category.LAUNCHER')
app.append(main_act)
settings_act = ET.Element('activity')
settings_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.SettingsActivity")
settings_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
settings_act.set('{http://schemas.android.com/apk/res/android}screenOrientation', 'landscape')
app.append(settings_act)
xml_str = ET.tostring(root, encoding='unicode')
dom = minidom.parseString(xml_str)
pretty = dom.toprettyxml(indent="    ")
pretty = '\n'.join(pretty.split('\n')[1:]) if pretty.startswith('<?xml') else pretty
with open(manifest_file, 'w') as f: f.write(pretty)
print("✅ AndroidManifest 已更新（横屏+图标）")
PYEOF
python3 /tmp/fix_manifest.py
rm -f /tmp/fix_manifest.py
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"
echo "✅ 权限和 cleartext 已添加"

# ==================== 构建并安装 ====================
echo "🧹 清理并构建..."
./gradlew clean
./gradlew assembleDebug
APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
    if command -v adb &> /dev/null; then
        echo "📲 安装 APK（覆盖安装，保留数据）..."
        adb install -r "$APK_PATH"
        echo "✅ 安装完成！"
    else
        echo "⚠️ adb 未找到，跳过安装。APK 位于: $APK_PATH"
        echo "您可以通过 adb install -r $APK_PATH 手动安装"
    fi
else
    echo "❌ 构建失败，未找到 APK"
    exit 1
fi
echo ""
echo "🎉 部署完成！"
echo "📌 固定签名: $KEYSTORE_FILE"
echo "📱 应用已强制横屏，弹窗为酷9风格（含进度条、网速开关）"
