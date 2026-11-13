# 探测与备份

任何改动之前先做这两件事。全部是只读操作。

## 开 ADB

设置 → 关于本机 → **本机信息** → 遥控器**缓慢**按 `上上下下左右左右`
→ 工厂菜单 → 通用设置 → **ADB** → 开。

> 序列是 `上上下下左右左右`，**不是** `上上下下左左右右`（后者进的是"快速演示模式"）。
> 按完要**等几秒**才会有反应，别急着按别的键。

验证：

```powershell
Test-NetConnection <tv-ip> -Port 5555
```

首次连接时电视会弹「允许 USB 调试」，选允许。

## 探测

```powershell
$env:TV_HOST = '<tv-ip>'
$py = 'tools\venv\Scripts\python.exe'

& $py -I tools/tv.py --probe        # 型号 / 机芯 / 版本 / 固件
& $py -I tools/tv.py 'getprop persist.service.homepage.pkg'
& $py -I tools/tv.py 'getprop persist.service.homepage.cls'
& $py -I tools/tv.py 'getprop ro.build.skymodel'     # 真实机芯，比 ro.product.model 可靠
& $py -I tools/tv.py 'getprop ro.build.skymid'       # 芯片
& $py -I tools/tv.py 'cat /system/pcfg/<机芯>/config/general_config.xml'
& $py -I tools/tv.py 'uname -a'
& $py -I tools/tv.py 'pm list packages'
```

本机 `--probe` 的实际输出：

```
ro.product.model            = 7S85_A9
ro.product.device           = 6A658B
ro.build.version.release    = 8.0.0
ro.build.version.sdk        = 26
ro.build.display.id         = OPR5.170623.014 dev-keys
ro.product.manufacturer     = Skyworth
ro.adb.secure               = 1
service.adb.tcp.port        = 5555
```

## 备份（必做）

下面这些存到一个目录里，出问题全靠它：

```powershell
$backup = 'backup'
New-Item -ItemType Directory -Force $backup | Out-Null

function Dump($cmd, $file) {
    (& $py -I tools/tv.py $cmd 2>$null) | Set-Content (Join-Path $backup $file) -Encoding UTF8
}

Dump 'pm list packages'      'packages.txt'
Dump 'pm list packages -d'   'disabled.txt'
Dump 'pm list packages -e'   'enabled.txt'
Dump 'getprop'               'getprop.txt'
Dump 'settings list secure'  'settings-secure.txt'
Dump 'settings list global'  'settings-global.txt'
Dump 'settings list system'  'settings-system.txt'
Dump 'dumpsys package com.tianci.movieplatform' 'stock-home-dumpsys.txt'
```

本机实测规模：73 个包、617 行 `getprop`、三份 settings 各 45～75 行。

## 恢复

```powershell
# 单个
& $py -I tools/tv.py 'pm enable --user 0 <包名>'

# 全部（对照 disabled.txt）
Get-Content backup\disabled.txt | Where-Object { $_ -match '^package:' } | ForEach-Object {
    $p = $_.Substring(8)
    & $py -I tools/tv.py "pm enable --user 0 $p"
}
```

## 关掉 ADB

调试完别长期开着——5555 是**明文**端口，同网段任何设备都能拿到 shell。

- 界面：工厂菜单 → 通用设置 → ADB → 关
- 或 ADB 命令：

  ```powershell
  & $py -I tools/tv.py 'setprop persist.sys.openadb 0'
  ```

  （本机实测：改完需重启，adbd 才会停，端口才真正关闭。）
