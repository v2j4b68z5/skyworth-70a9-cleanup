# 踩坑记录

按"最意外"排序。前四条是本机独有的，公开资料里没有。

---

## 1. 原桌面被顶掉后仍在后台满负荷空转

第三方桌面接管后，`com.tianci.movieplatform` **不会退出**：

```
$ dumpsys cpuinfo
 115% com.tianci.movieplatform: 86% user + 29% kernel
```

一个屏幕上完全看不见的进程，占着 **115% CPU 和 279 MB 内存**。每次按 Home，固件还会把它
重新拉起（实测 `ps` 里出现新 PID）。

**处理**：守护脚本在切换后立刻 `am force-stop`，之后每 5 秒检查一次是否复活。
这是本次改造**最大**的性能收益，远超精简预装包。

---

## 2. `pm install` 被自家安全组件拦截

```
Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]
```

`logcat` 显示 `com.coocaa.os.manager.security.perm.install.AdbInstallActivity` 抢到前台弹确认框，
而 `pm install` 不等待人工确认，于是立刻返回"用户取消"。

**处理**：`-i com.tianci.appstore` 把安装来源伪装成它自家商店。
注意 `-i com.android.vending` **无效**，只有厂商自己的包名放行。

---

## 3. 无障碍服务设置了却永不绑定

`settings put secure enabled_accessibility_services` 写入成功、`accessibility_enabled=1`、
组件在 `dumpsys package` 里注册正常，但：

```
$ dumpsys accessibility
           services:{}
$ dumpsys activity services com.coocaa.tvhome
  (nothing)
```

重启后依旧。**这台固件的 `AccessibilityManagerService` 不绑定任何服务**，
所以一切依赖无障碍的方案（包括 cleanyourtv 的 `stock_home_redirect` 与 PR #1455）全部失效。

---

## 4. 同型号「70A9」= 至少五种机芯

网上搜到的刷机包：

| 来源 | 机芯 |
|---|---|
| ZNDS 分享帖 | 7S711 |
| 刷机小站精简版 | 7S70 |
| 各求助帖 | 8A002 / 9R66 |
| **本机** | **7S86** |

`ro.product.model` 还报 `7S85_A9`，只有 `ro.build.skymodel` 才是真实机芯 **7S86**。
**报参数时务必报机芯，不要报型号名。**

---

## 5. 固件会把已停用的包重新启用

`com.tianci.ad` 在某次重启后自己回到了启用状态（停用清单 14 → 13）。
不处理的话开机广告会回来。

**处理**：守护脚本里的 ad guard，每 60 秒复核三个广告类包。

---

## 6. `device user is locked` 之外的静默失败

几乎所有失败都是**静默的**——没有异常、没有 toast、没有日志：

| 操作 | 表象 |
|---|---|
| `set-home-activity` | 打印 `Success`，实际无效 |
| `stock_home_redirect` | 设置生效，但服务不绑定 → 静默关闭 |
| `boot_to_live_tv` | 配置正确、构建包含，`liveTvIntent()` 返回 null → 直接 `return false` |
| `settings put global SKY_SYSTEM_ENV_BOOT_START_HOME_PAGE` | 值持久化，固件不读 |
| shim 的开机监视 | 连日志目录都不创建 |

**教训**：每一步都必须找到**可观测的判据**（`dumpsys accessibility` 的 `services:{}`、
`ps`、`dumpsys cpuinfo`、`/data/.../watch.log`），不能相信命令的返回码或 `Success`。

---

## 7. Windows 构建三连坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `Could not create parent directory for lock file ...\.gradle\...` | `%USERPROFILE%` 不可写 | `GRADLE_USER_HOME` 指到可写目录 |
| `Failed to apply plugin 'com.android.internal.application'` | `~/.android` 不可写 | `ANDROID_USER_HOME` 指到可写目录 |
| `AccessDeniedException: ...\AppData\Local\Temp\tempdir_*` | Java 临时目录被拒 | `TEMP`/`TMP` + `-Djava.io.tmpdir` |

还有两个下载源：

- Adoptium 官方源在国内**被重置**（0 字节）→ 用清华镜像
- `services.gradle.org` 的 gradle 分发包 **HEAD 能通、GET 卡在 0 字节** → 用腾讯镜像，
  并用 `gradle-wrapper.properties` 里的 sha256 校验（两者一致）

---

## 8. PowerShell 脚本的两个编码坑

1. **`.ps1` 里的中文字符串字面量**：Windows PowerShell 5.1 按 ANSI 读无 BOM 的 UTF-8 文件，
   中文变乱码后引号错位 → `The string is missing the terminator`。
   本仓库的脚本因此**全部只用英文**，中文写在文档里。
2. **`$args` 是自动变量**：`$args = @(...)` 会把参数数组覆盖掉，导致 `Start-Process` 行为异常。
   改用 `$argList`。

---

## 9. 子进程里找不到 `pwsh`

在 `pwsh` 里 `pwsh -File ...` 会报"无法将 pwsh 项识别为 cmdlet"（子进程 PATH 里没有）。
用 `powershell -File ...`，或绝对路径。
