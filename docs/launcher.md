# 桌面：编译与配置

用的是 [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv) 的参考桌面，
从源码编译，**包名必须改成 `com.coocaa.tvhome`**。

## 为什么必须改包名

酷开的内存管理器会在第三方应用离开屏幕约两秒后强杀它，但**放过 `com.coocaa.*` 包名的应用**。
用默认的 `com.gathin.tvhome` 装上去，一切换到别的 App 桌面就被杀，返回时已经没了。

```bash
./gradlew assembleRelease -PlauncherApplicationId=com.coocaa.tvhome
```

## 编译环境（无 JDK / SDK 的机器）

本机原本什么构建工具都没有（java / gradle / android sdk 全无）。从零搭：

```powershell
# JDK 17（清华镜像，Adoptium 官方源在国内常被重置）
#   https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/
# Android SDK（dl.google.com 在国内可用）
#   platforms;android-34 / build-tools;34.0.0
# Gradle 8.9（腾讯镜像；services.gradle.org 下载会卡在 0 字节）
#   https://mirrors.cloud.tencent.com/gradle/gradle-8.9-bin.zip
#   sha256 d725d707bfabd4dfdc958c624003b3c80accc03f7037b5122c4b1d0ef15cecab
```

四个环境变量必须都指向**可写目录**，否则会在 `%USERPROFILE%` 下被拒：

```powershell
$env:JAVA_HOME         = '<jdk>'
$env:ANDROID_HOME      = '<sdk>'
$env:ANDROID_SDK_ROOT  = '<sdk>'
$env:ANDROID_USER_HOME = '<writable>'   # 否则报 C:\Users\<you>\.android 不可写
$env:GRADLE_USER_HOME  = '<writable>'   # 否则 wrapper 建不了锁文件
$env:TEMP = $env:TMP   = '<writable>'   # 否则打包阶段 AccessDeniedException
```

`gradle assembleRelease` 时再加 `-Djava.io.tmpdir=<writable>`。产物约 **574 KB**。

## 适配这台电视的配置

仓库只允许改 `launcher/app/src/main/res/values/config.xml`（或一个主题的 `config.json`）。
本机的改动：

### 1. `app_library` 必须打开

**这台电视上几乎没有 App 声明 `LEANBACK_LAUNCHER`。** 不开这个开关，桌面网格里只有 1 个图标
（应用圈），dock 也会退化成"前四个网格 App"。

```xml
<bool name="app_library">true</bool>
<string-array name="library_apps">
    <item>com.gitv.dvb.live</item>
    <item>com.newtv.cboxtv</item>
    ...
</string-array>
```

### 2. `dock_apps` 只认 `config.xml`

放在设备上的 `config.json`（主题机制）**覆盖不了 `dock_apps`**——但同一个文件里的
`coocaa_sources` 是生效的。这个不对称很容易误判成"配置没读进去"，本机为此多编了一版。

### 3. `coocaa_sources` + 控制中心服务

酷开不向 `TvInputManager` 注册任何输入，HDMI/AV 列表要从 `com.skyworth.tv` 自己取：

```xml
<bool name="coocaa_sources">true</bool>
<string name="source_panel_service">com.coocaa.os.ccosservice/com.coocaa.os.centerintegration.service.CenterService</string>
<string name="source_panel_action">com.coocaa.intent.action.CONTROL_CENTER</string>
<string name="source_panel_extra">control_center_command=100</string>
```

### 4. `glow_snap`

Mali-G51 比文档里提到的 Mali-G52 还慢。`glow_snap=true` 让焦点换颜色时一帧切完，
而不是每帧重绘整屏（一次按键约 40 帧）。

### 5. `boot_to_live_tv`：本机走不通

```xml
<string name="live_tv_package">com.tntlikely.xplayer</string>
<bool name="boot_to_live_tv">true</bool>
```

配了，但**没有效果**。原因在 `MainActivity.liveTvIntent()`：

1. 先用 `getLeanbackLaunchIntentForPackage()` —— xplayer 是普通应用，返回 null
2. 再用配置的 `live_tv_action` 解析 —— `Intent("android.intent.action.MAIN").setPackage(pkg)`
   在本机固件上 `resolveActivity` 返回 null（实测 `am start` 报 `unable to resolve`）
3. 于是返回 null，`openLiveTvAfterBoot()` 静默放弃

这个缺口有两处小补丁（`live_tv_action` 兜底 + 代码回退到 `getLaunchIntentForPackage`），
但本机最终是**改用守护脚本打开直播**的——一条路径、可控、可验证。见 [guard.md](guard.md)。

## 安装

酷开有安装拦截，`pm install` 会直接失败：

```
Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]
```

`logcat` 里能看到是 `com.coocaa.os.manager.security.perm.install.AdbInstallActivity` 在前面拦。
**把安装来源伪装成它自家商店就能过**：

```powershell
& $py -I tools/b64push.py <apk> /data/local/tmp/app.apk
& $py -I tools/tv.py 'pm install -r -i com.tianci.appstore /data/local/tmp/app.apk'
```

偶发仍会失败一次，**重试即可**（本机四个 App 里有两个第一次被拦、第二次成功）。

> 推送用 `tools/b64push.py`（分块 base64），不要用标准 adb push：
> 本机 `adb_shell` 的文件同步会报 `PushFailedError: secure_mkdirs failed`。
