# 局域网守护：不 root 也能开机进第三方桌面

## 思路

`cleanyourtv` 的 `stock_home_redirect` 是让**电视内部**的无障碍服务把原桌面顶掉。
本机无障碍服务不绑定（见 [evidence.md](evidence.md) 第 6 条），电视自己做不到。

那就换个执行者：**同一局域网里的一台常开电脑**，用 ADB 代替电视做同样的事。

```
每 5 秒读一次电视前台窗口（dumpsys window），然后分三种情况：

① 酷开原桌面在前台
   → setprop persist.service.homepage.pkg com.coocaa.tvhome
   → setprop persist.service.homepage.cls com.gathin.tvhome.MainActivity
   → am start -n com.coocaa.tvhome/com.gathin.tvhome.MainActivity
   → am force-stop com.tianci.movieplatform        ← 关键：它退出前台后仍占 115% CPU

② 第三方桌面在前台
   → 检查原桌面进程是否在后台复活，发现就再强停
   → 若本次开机还没开直播 App，拉起它（最多重试 3 次）

③ 别的 App / 输入源在前台
   → 什么都不做。绝不打断正在看的内容。
```

## 为什么第 ④ 步（强停原桌面）是最有价值的

实测这台电视上，`com.tianci.movieplatform` 被第三方桌面顶掉之后**并没有退出**：

```
$ dumpsys cpuinfo
 115% com.tianci.movieplatform: 86% user + 29% kernel
  45% tvserver
  23% system_server
  22% com.tianci.system
  19% com.tianci.user
  16% com.coocaa.os.ccosservice
```

它占着 **279 MB 内存** 和 **115% CPU**（超过一个核心），屏幕上却什么都看不到。
强停之后，整台机器的 CPU 占用立刻掉到最高 24%（且是音频 HAL，不是 App）：

```
杀掉前：6 个进程 15%～115%
杀掉后：24% mstar.hardware.audio / 4.3% system_server / 3.1% irq
```

**这是本次改造里最大的一笔性能收益**，比卸载任何预装 App 都管用。

## 部署

### 1. 前置

- 电视和电脑在**同一局域网**
- 电视已开网络 ADB（5555）：本机信息页 → 遥控器缓慢按 `上上下下左右左右`
  → 工厂菜单 → 通用设置 → ADB
- 电脑装有 PowerShell 5.1+ 与 Python 3（脚本用 `cleanyourtv` 的纯 Python ADB 客户端）

### 2. 准备 cleanyourtv 的 Python ADB 客户端

```powershell
git clone https://github.com/Gathin23/cleanyourtv.git
cd cleanyourtv
python -m venv tools\venv
tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt
```

> 依赖只有三个：`adb-shell`、`rsa`、`cryptography`。
> 如果 pip 在用户缓存目录报「拒绝访问」，加 `--no-cache-dir` 并把 `PIP_CACHE_DIR` 指到可写目录。

### 3. 跑起来

```powershell
powershell -ExecutionPolicy Bypass -File scripts\watch-home.ps1 -TvHost <tv-ip>
```

Ctrl+C 停止。

### 4. 开机自启（不用管理员）

`schtasks` 需要管理员权限。用当前用户的注册表 Run 键即可：

```powershell
$script = (Resolve-Path 'scripts\watch-home.ps1').Path
$cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '" -TvHost <tv-ip> -IntervalSeconds 5'
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'TV Home Watcher' -Value $cmd -PropertyType String -Force
```

凭据存在 `HKCU`，不需要提权，下次登录 Windows 自动启动。

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-TvHost` | *必填* | 电视局域网 IP |
| `-IntervalSeconds` | `5` | 轮询间隔 |
| `-NoKill` | off | 只切桌面，不强停原桌面（省 CPU 的那半功就没了） |
| `-LiveTv` | `com.tntlikely.xplayer/com.tntlikely.xplayer.MainActivity` | 开机要自动打开的 App，改成 `-NoLiveTv` 关闭 |
| `-NoLiveTv` | off | 关闭开机自动进直播 |

## 已知限制

| 限制 | 说明 |
|---|---|
| 电脑必须开着 | 电视开机时电脑不在线，就停在酷开桌面；按一下遥控器 Home 即可用 |
| 开机先闪 1～2 秒原桌面 | 固件那行 `DEFAULT_HOMEPAGE` 决定的，跳不过去 |
| 直播最多重试 3 次 | 固件有时会在开机后恢复上一次的 App 盖住它，重试只在桌面处于前台时进行，不会抢你正在用的 App |
| ADB 明文 | 5555 是明文端口，建议只在内网使用，并用完关掉 |

## 排错

| 现象 | 检查 |
|---|---|
| 一直 `TV not reachable` | `Test-NetConnection <tv-ip> -Port 5555`；电视 ADB 是否被关 |
| 桌面切过去了但很卡 | 看 `ps -A \| grep movieplatform`，有就是 `-NoKill` 开着 |
| 开机没进直播 | 看日志里 `boot #N, live TV attempt x/3`；确认包名正确 |
| 桌面被固件抢回 | 日志里应有 `stock Coocaa home in front -> taking over`；没有就是电脑没连上 |

## 停止 / 回滚

- 停守护：结束 `watch-home.ps1` 的 powershell 进程；永久停则删注册表 Run 项
- 恢复原桌面属性：

  ```powershell
  & $py -I tools/tv.py 'setprop persist.service.homepage.pkg com.tianci.movieplatform'
  & $py -I tools/tv.py 'setprop persist.service.homepage.cls com.coocaa.homepage.vast.HomePageActivity'
  ```

- 卸载第三方桌面：`pm uninstall com.coocaa.tvhome`
