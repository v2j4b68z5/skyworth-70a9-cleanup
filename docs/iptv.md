# 直播源：哪份能播，怎么自己测

结论先说：**列表大小没有意义，可用率天差地别。** 同一个晚上，同一台电视、同一条宽带：

| 列表 | 频道数 | 抽样实测 | 可用 |
|---|---|---|---|
| **vbskycn/iptv** `tv/iptv4.m3u` | 427 | 8 → 扩到 14 | **8/8，13/14 真 HLS** |
| mytv-android `China-TV-Live-M3U8` | 21 | 21 | 可用（小而精） |
| akiralereal/iptv `IPTV.m3u` | 20 | 20 | 部分可用 |
| iptv-org `streams/cn.m3u` | 518 | 8 | 2/8 |
| fanmingming/live `index.m3u` | 94 | 8 | **0/8（全 404）** |
| fanmingming/live `itv.m3u` | 189 | 8 | **0/8（全 403）** |
| YanG-1989/m3u `Gather.m3u` | 123 | 8 | **0/8（全 403）** |

> fanmingming 那份列表曾经很火，但它的央视流现在带防盗链，第三方直连一律 403/404。
> **"有 94 个台"和"能看 94 个台"是两件事。**

## 用脚本自己测

```powershell
# 用内置的候选列表（7 份）
powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1

# 用自己的列表（一行一个 URL，# 开头是注释）
powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1 -Sources my-sources.txt

# 拉列表需要代理时（注意：流测试故意不走代理）
powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1 -Proxy http://127.0.0.1:10808
```

输出：

- `_serve\verified\merged.m3u` —— **只包含返回真 HLS 的流**，去重后的合并清单
- `_serve\verified\report.csv` —— 每条流的通过/失败明细

判定标准：`curl` 拿到 200 **且** 正文包含 `#EXTM3U`。只看状态码不够——有些 200 是错误页。

## 怎么送到电视上

电视本身**上不了 GitHub**（实测 `raw.githubusercontent.com`、`cdn.jsdelivr.net`、`ghproxy.net`、
`gh-proxy.com`、`ghfast.top`、`raw.gitmirror.com` 全部超时）。所以：

1. 在电脑上跑脚本，得到 `merged.m3u`
2. 电脑起一个 HTTP 服务把它发到局域网：

   ```powershell
   python -m http.server 8099 --bind 0.0.0.0 --directory <merged.m3u 所在目录>
   ```

3. 电视上的播放器订阅 `http://<电脑局域网IP>:8099/merged.m3u`

**已验证**：电视侧 `busybox wget` 能把这份 28 KB 的清单完整拉下来（Windows 防火墙默认放行，
不需要额外规则）。

## 播放器怎么填源

以 **myTV（电视直播）** 为例，它有完整的 HTTP API，可以完全不碰遥控器：

```text
GET  /api/configs                      取全部配置
POST /api/configs                      写配置（含 iptvSourceList / iptvSourceCurrentIdx）
POST /api/file/content-with-dir        往电视写文件 {dir, filename, content}
GET  /api/file/content?path=...         读电视上的文件
```

源类型：`0` = 远程 URL，`1` = 本地文件，`2` = Xtream，`3` = Stalker。

**踩过的坑**：只把 `iptvSourceList` 写进去不够，`iptvSourceCurrentIdx` 必须是 `0`，
否则 App 视为"未选中源"，频道列表一片空白。而且这个索引**只能在 App 的源列表里点
「设为当前」才会稳定生效**——直接 POST 会被归一化回 `-1`。

操作路径：`设置 → 订阅源 → 自定义订阅源 → 点源卡片 → 设为当前 → 刷新全部`。

## 一点背景

央视对第三方直连做了限流，所以任何"公开直连列表"的可用率都会随时间波动。
本机 2026-11-13 17:05 的实测结果是 **111 条抽样 → 64 条通过 → 去重后 62 个频道**，
这份合并清单成了电视上实际使用的源。

过一段时间如果发现大片失效，重跑一次 `test-sources.ps1` 就行。
