# 精简：14 个包

全部用 `pm disable-user --user 0`，**不卸载**。卸载系统应用在这台机器上没有任何性能收益
（停用的包同样不启动、不占内存、不占 CPU），却会失去可恢复性——所以只停用。

一条命令可恢复：

```powershell
& $py -I tools/tv.py 'pm enable --user 0 <包名>'
```

## 清单

见 [`../scripts/debloat-70A9.txt`](../scripts/debloat-70A9.txt)（带逐条注释）。
直接应用（用 cleanyourtv 的脚本，它会先写恢复记录再动手）：

```powershell
$env:TV_HOST = '<tv-ip>'
tools\disable.sh scripts\debloat-70A9.txt
```

## 分两批做的原因

一次全关，出问题不知道是哪个。实际执行时分了两批，每批之后截图确认：

**批次 1（纯广告/遥测，5 个）** —— 零风险

| 包 | 说明 |
|---|---|
| `com.tianci.ad` | 开机广告 Activity |
| `com.tianci.push` | 推送 + 神策行为统计 |
| `com.coocaa.sysreport` | 使用上报（开机 / 切屏 / 装应用） |
| `com.tianci.autoinstaller` | **静默安装推广 App** |
| `com.baidu.oases` | 百度 SDK 开机自启 |

**批次 2（无用预装，9 个）** —— 不影响任何日常功能

屏保广告、主题商店、系统消息盒、客服/帮助、儿童教育、生活助手、电视管家、商场演示、开机引导。

两个批次之后桌面与遥控均正常，`pm list packages -d` 复核 14 个全部为 `disabled-user`。

## 固件会偷偷把包启用回来

实测：`com.tianci.ad` 在某次重启后**被固件重新启用**（停用清单从 14 个变成 13 个）。
这不是误操作，是固件自己的行为。

`scripts/watch-home.ps1` 里有一个守卫：每 60 秒检查 `com.tianci.ad` / `com.coocaa.guide` /
`com.skyworth.skymarket`，发现被启用就立刻再停用。所以**开机广告不会再回来**。

验证方法：

```powershell
& $py -I tools/tv.py 'pm list packages -d'
```

## 效果

| 指标 | 之前 | 之后 |
|---|---|---|
| 停用包 | 0 | 14 |
| 可用内存 | 1.05 GB | 1.15 GB |
| 开机视频 | 15 秒 | 1 秒（`persist.sys.bootvideo.time 1`） |
| 开机广告 | 有 | 无（`logcat` 里 `BootViewActivity` 零记录） |

> 真正让电视变顺的不是这 14 个包，而是**强停原桌面**——它一个人就占 115% CPU。
> 见 [guard.md](guard.md)。
