# test-sources.ps1 -- find out which IPTV playlists actually play, then build one
# merged playlist of only the streams that answered.
#
# Why: a 400-channel list where every stream returns 403 is worth nothing. On a Skyworth
# 70A9 / 7S86_A9 the lists behave very differently -- fanmingming's list was 0/16,
# vbskycn/iptv was 13/14 on the same evening. Measuring first saves an evening.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1 -Sources sources.txt
#   powershell -ExecutionPolicy Bypass -File scripts\test-sources.ps1 -Proxy http://127.0.0.1:10808
#
# -Sources is a text file, one playlist URL per line (# starts a comment).
# Without it the built-in candidate list below is used.
#
# Output:
#   <OutDir>\merged.m3u     only the streams that returned a real HLS playlist
#   <OutDir>\report.csv     per-stream result, and a per-source summary at the end
#
# Note: fetching the playlists may need a proxy on networks where GitHub is blocked, but
# the STREAM tests deliberately run without one -- that is the path the TV itself takes.

param(
    [string]$Sources  = '',
    [string]$OutDir   = '_serve\verified',
    [string]$Proxy    = '',
    [int]$TimeoutSec  = 5,
    [int]$PerSource   = 45,
    [string]$MatchOn  = 'CCTV|卫视|新闻|电影|体育|纪录|少儿|地方|都市|影视|综合'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

$defaultSources = @(
    @{ name = 'vbskycn/iptv';        url = 'https://raw.githubusercontent.com/vbskycn/iptv/master/tv/iptv4.m3u' },
    @{ name = 'mytv China-TV-Live';  url = 'https://raw.githubusercontent.com/mytv-android/China-TV-Live-M3U8/main/iptv.m3u' },
    @{ name = 'akiralereal/iptv';    url = 'https://raw.githubusercontent.com/akiralereal/iptv/main/IPTV.m3u' },
    @{ name = 'iptv-org cn';         url = 'https://raw.githubusercontent.com/iptv-org/iptv/master/streams/cn.m3u' },
    @{ name = 'fanmingming index';   url = 'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/index.m3u' },
    @{ name = 'fanmingming itv';     url = 'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/itv.m3u' },
    @{ name = 'YanG-1989/m3u';       url = 'https://raw.githubusercontent.com/YanG-1989/m3u/main/Gather.m3u' }
)

$list = @()
if ($Sources) {
    if (-not (Test-Path $Sources)) { throw "sources file not found: $Sources" }
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path $Sources))) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $n++
        $list += @{ name = ("source $n"); url = $t }
    }
}
else { $list = $defaultSources }

function Parse-Playlist([string]$file) {
    $lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)
    $res = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#EXTINF') {
            $info = $lines[$i]
            for ($j = $i + 1; $j -lt [Math]::Min($i + 4, $lines.Count); $j++) {
                if ($lines[$j] -and -not $lines[$j].StartsWith('#')) {
                    $res += [pscustomobject]@{
                        info = $info
                        url  = $lines[$j].Trim()
                        name = ($info -split ',', 2)[-1].Trim()
                    }
                    break
                }
            }
        }
    }
    return $res
}

function Test-Stream([string]$url, [int]$timeout) {
    # No proxy here on purpose: this is the path the TV takes.
    $body = & curl.exe -s -m $timeout -L $url 2>$null
    if (($body -join "`n") -match '#EXTM3U') { return $true }
    return $false
}

$summary = @()
$rows = @()
$merged = New-Object System.Collections.Generic.List[string]
$merged.Add('#EXTM3U')
$seen = @{}

foreach ($s in $list) {
    $safe = ($s.name -replace '[^\w\.-]', '_')
    $local = Join-Path $OutDir ("$safe.m3u")

    Write-Host ("[{0}] downloading {1}" -f $s.name, $s.url)
    if ($Proxy) {
        & curl.exe -sSL --proxy $Proxy --retry 1 --max-time 60 -o $local $s.url 2>$null
    } else {
        & curl.exe -sSL --retry 1 --max-time 60 -o $local $s.url 2>$null
    }
    if (-not (Test-Path $local) -or (Get-Item $local).Length -lt 200) {
        Write-Host ("          download failed, skipped")
        $summary += [pscustomobject]@{ source = $s.name; listed = 0; tested = 0; passed = 0; note = 'download failed' }
        continue
    }

    $all = @(Parse-Playlist $local)
    $pick = @($all | Where-Object { $_.name -match $MatchOn } | Select-Object -First $PerSource)
    if ($pick.Count -eq 0) { $pick = @($all | Select-Object -First $PerSource) }

    $pass = 0
    foreach ($c in $pick) {
        $key = $c.name.ToLower()
        if ($seen.ContainsKey($key)) { continue }
        $ok = Test-Stream $c.url $TimeoutSec
        $rows += [pscustomobject]@{ source = $s.name; channel = $c.name; ok = $ok; url = $c.url }
        if ($ok) {
            $seen[$key] = 1
            $pass++
            $merged.Add($c.info)
            $merged.Add($c.url)
        }
    }
    $summary += [pscustomobject]@{ source = $s.name; listed = $all.Count; tested = $pick.Count; passed = $pass; note = '' }
    Write-Host ("          tested {0}, passed {1}" -f $pick.Count, $pass)
}

$mergedFile = Join-Path $OutDir 'merged.m3u'
[System.IO.File]::WriteAllLines($mergedFile, $merged, (New-Object System.Text.UTF8Encoding($false)))
$rows | Export-Csv -Path (Join-Path $OutDir 'report.csv') -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '=== summary ==='
$summary | ForEach-Object {
    Write-Host ("  {0,-24} listed {1,-5} tested {2,-4} passed {3,-4} {4}" -f `
        $_.source, $_.listed, $_.tested, $_.passed, $_.note)
}
Write-Host ''
Write-Host ("merged playlist: {0}  ({1} channels, {2} KB)" -f `
    $mergedFile, $seen.Count, [math]::Round((Get-Item $mergedFile).Length / 1KB, 1))
Write-Host 'Serve it over HTTP on the LAN and point the TV app at that URL, or copy it to a USB drive.'
