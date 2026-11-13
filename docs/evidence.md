# 证据链：为什么 7S86_A9 的开机桌面改不了

每条路线都是在这台真机上实测的，命令与输出原样保留（IP 已替换为 `<tv-ip>`）。
工具用 `cleanyourtv` 自带的纯 Python ADB 客户端，避免依赖 `adb.exe`。

```powershell
$env:TV_HOST = '<tv-ip>'
$py = 'tools\venv\Scripts\python.exe'
& $py -I tools/tv.py '<命令>'
```

---

## 0. 前置事实

```
$ cmd package resolve-activity --brief -c android.intent.category.HOME
No activity found
```

酷开的桌面**不声明标准 `CATEGORY_HOME`**，它用的是私有类别：

```
com.tianci.movieplatform/com.ccos.cooui.movieplatform.MainActivity
  Category: "android.intent.category.HOME.CC"
  Category: "android.intent.category.HOME.CC_MAIN"
```

而开机实际拉起的 `com.coocaa.homepage.vast.HomePageActivity` **一个 home 类别都不声明**，
它的名字只出现在一条系统属性里：

```
$ getprop persist.service.homepage.cls
com.coocaa.homepage.vast.HomePageActivity
```

**这一条就解释了后面所有"静默失效"**：任何依赖 Android HOME 解析的方案在这里都无效。

---

## 1. 停用原桌面 → 固件重新启用并强行拉起

```
$ pm disable-user --user 0 com.tianci.movieplatform
Package com.tianci.movieplatform new state: disabled-user
$ input keyevent KEYCODE_HOME
$ dumpsys window | grep mCurrentFocus
mCurrentFocus=Window{... com.tianci.movieplatform/com.coocaa.homepage.vast.HomePageActivity}
```

重启后：

```
$ pm list packages -d | grep movieplatform
package:com.tianci.movieplatform        ← 仍显示已停用
$ dumpsys window | grep mCurrentFocus
mCurrentFocus=Window{... com.tianci.movieplatform/...HomePageActivity}
```

**包状态是「已停用」，活动却照样在前台**——固件用系统身份直接拉起，绕过停用状态。

---

## 2. `persist.service.homepage.*` 重启被写回

```
$ setprop persist.service.homepage.pkg com.coocaa.tvhome
$ setprop persist.service.homepage.cls com.gathin.tvhome.MainActivity
$ reboot
$ getprop persist.service.homepage.pkg
com.tianci.movieplatform                ← 被改回去了
```

固件配置里写着来源：

```
$ cat /system/pcfg/7S86_A9/config/general_config.xml | grep DEFAULT_HOMEPAGE
<config name="DEFAULT_HOMEPAGE" value="com.tianci.movieplatform/com.coocaa.homepage.vast.HomePageActivity"/>
<config name="NEW_BOOT_FLOW"    value="true"/>
```

---

## 3. `persist.service.model.*` 重启被清空

```
$ setprop persist.service.model.pkg com.coocaa.tvhome
$ setprop persist.service.model.cls com.gathin.tvhome.MainActivity
$ reboot
$ getprop persist.service.model.pkg
                                        ← 空
```

> 反例：另一台酷开（`7S77_G650P`，build `022.009.080`）上这条路径**有效**，
> 见 [cleanyourtv#1938](https://github.com/Gathin23/cleanyourtv/issues/1938)。
> **同代固件、同一个开关，行为不同**——这就是酷开最坑的地方。

---

## 4. `set-home-activity` 报成功但无效

```
$ cmd package set-home-activity com.coocaa.tvhome/com.gathin.tvhome.MainActivity
Success
$ reboot
$ input keyevent KEYCODE_HOME
$ dumpsys window | grep mCurrentFocus
mCurrentFocus=Window{... com.tianci.movieplatform/...HomePageActivity}
```

---

## 5. shim 方案：`BOOT_COMPLETED` 根本不投递

`coocaa-home-shim` 的思路是注册一个包名 `com.ccos.tv.homepage` 的跳板，
靠开机广播把自己重写回属性里。本机实测：

- 包已安装、`BootReceiver` 在 `enabledComponents` 里
- 属性 `persist.service.model.pkg` 确实被固件改成了 `com.ccos.tv.homepage`
- **但跳板从未被唤醒**：它的日志目录 `/sdcard/Android/data/com.ccos.tv.homepage/files/`
  **根本不存在**——`BootWatchService` 一次都没跑过

```
$ ls -l /sdcard/Android/data/com.ccos.tv.homepage/files/
ls: ...: No such file or directory
```

结论：第三方 App 收不到 `BOOT_COMPLETED` / `LOCKED_BOOT_COMPLETED`
（同 [cleanyourtv#1938](https://github.com/Gathin23/cleanyourtv/issues/1938) 的记录）。

---

## 6. 无障碍服务：本机根本不绑定

`cleanyourtv` 的 `stock_home_redirect`（以及 PR #1455 的修法）整套逻辑跑在无障碍服务里。
本机设置全部写入成功：

```
$ settings get secure enabled_accessibility_services
com.coocaa.tvhome/com.gathin.tvhome.HomeKeyService
$ settings get secure accessibility_enabled
1
$ dumpsys package com.coocaa.tvhome | grep HomeKeyService
ce7ed73 com.coocaa.tvhome/com.gathin.tvhome.HomeKeyService filter 2ca8320   ← 组件注册正常
```

但系统一个都不绑，**重启后依旧**：

```
$ dumpsys accessibility
ACCESSIBILITY MANAGER (dumpsys accessibility)

User state[attributes:{id=0, currentUser=true, ...}
           services:{}]

$ dumpsys activity services com.coocaa.tvhome
ACTIVITY MANAGER SERVICES (dumpsys activity services)
  (nothing)
```

试过：清空再重设、`accessibility_enabled` 0→1 循环、先把桌面跑起来解除 stopped 状态——
**全部无效**。

> **这条对社区最有价值**：PR #1455 的验证前提在本机不成立。
> 已回帖到 [cleanyourtv#1351](https://github.com/Gathin23/cleanyourtv/issues/1351)。

---

## 7. settings 里没有后门

`setting_config.xml` 列出了所有可通过 `Settings` 读写映射的**创维自有键**：

```
$ cat /system/pcfg/7S86_A9/config/setting_config.xml
<item name="SKY_SYSTEM_ENV_BOOT_START_HOME_PAGE"/>
<item name="SKY_CFG_TV_BOOT_SOURCE"/>
<item name="SKY_CFG_TV_BOOT_VIDEO_SOUND_SWITCH"/>
...（共 50 余项，涵盖画面/声音/网络/CEC）
```

- **没有** `BOOT_AD`
- **没有** `DEFAULT_HOMEPAGE`
- **没有** `APP_SELF_INSTALL`

`SKY_SYSTEM_ENV_BOOT_START_HOME_PAGE` 是唯一名字相关的：写进去**能持久化**（重启后仍在），
但固件**不读它**，开机照样进原桌面。

---

## 8. 提权：Dirty COW 用不了

社区里 [skyworth-55g7200-debloat](https://github.com/Sisyphus1727/skyworth-55g7200-debloat)
用 CVE-2016-5195（Dirty COW）改 `/system/pcfg/<机芯>/config/general_config.xml`。

本机内核：

```
$ uname -a
Linux localhost 4.9.44+ #1 SMP PREEMPT Mon Aug 22 15:35:18 CST 2022 armv8l
```

Dirty COW 于 **2016-10** 修复（Linux 4.8.3 / 4.4.26 起），本机内核编译于 **2022-08**——
**该漏洞不存在**。这条路对本机彻底关闭。

---

## 9. 另一个不同代际的机制（本机没有）

`skyworth-tv-clean` 记录 8R145_A5D（Android 11）的开机流程读
`/system/ccos/etc/bootintent.xml`，按 `persist.service.model.pkg/cls` 拉起组件，
Home 键走 `persist.service.homepage.pkg/cls`——**两套不同路径**。

本机：

```
$ ls -l /system/ccos/etc/
ls: /system/ccos/etc/: No such file or directory
```

**这个文件不存在**，是更新的酷开才有的机制。

---

## 刷机为什么不可行

网上能搜到的「创维 70A9 刷机包」，机芯全部对不上：

| 来源 | 机芯 | 本机 |
|---|---|---|
| ZNDS「创维70A9/7S711刷机包免费分享」 | **7S711** | 7S86 |
| 刷机小站「70A9-7S70 当贝桌面精简版」 | **7S70** | 7S86 |
| ZNDS 各求助帖 | 8A002 / 9R66 | 7S86 |

**「70A9」是零售型号，不是机芯。** 同一个型号名下面至少有 7S70 / 7S711 / 8A002 / 9R66 / 7S86
五种主板，U 盘强刷（`MstarUpgrade.bin` + 按住机身键上电）刷错机芯的结果是
**黑屏 / 花屏 / 卡 COOCAA logo**，而且：

- 本机没有分区镜像备份
- 没有确认可用的原厂整机程序作为退路
- 已过保（整机 1 年）

**如果一定要刷，先做一件事**：打创维客服 `95105555`，报机芯 **7S86**，索取整机程序作为退路。
拿不到退路就别刷。

---

## 小结

| 想改的东西 | 位置 | 能否免 root 修改 |
|---|---|---|
| `DEFAULT_HOMEPAGE` | `/system/pcfg/7S86_A9/config/general_config.xml` | ❌ /system 只读 |
| `BOOT_AD` / `SUPPORT_POWER_OFF_AD` | 同上 | ❌（但停用广告包等效，见 [debloat.md](debloat.md)） |
| `APP_SELF_INSTALL` | 同上 | ❌（但 `-i com.tianci.appstore` 等效） |
| Home 键归谁 | `persist.service.homepage.*` | ⚠️ 当次有效，重启被改回 |
| **开机落点** | 固件硬编码 | ✅ **靠局域网守护**（见 [guard.md](guard.md)） |
