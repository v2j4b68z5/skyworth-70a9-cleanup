# watch-home.ps1 -- keep a CleanYourTV launcher as the visible Home on a Skyworth 70A9 / 7S86_A9
# (Coocaa OS, Android 8.0), keep the stock Coocaa home from burning a core, and open the live TV
# app once per boot.
#
# Why this exists: the firmware hardcodes the boot home in
#   /system/pcfg/7S86_A9/config/general_config.xml -> DEFAULT_HOMEPAGE
# on the read-only /system partition. persist.service.homepage.* is rewritten at boot,
# persist.service.model.* is cleared at boot, BOOT_COMPLETED never reaches a third-party
# receiver, and AccessibilityManagerService binds no service at all -- so the TV cannot
# redirect Home by itself. See docs/evidence.md in this repository.
#
# So a machine on the same LAN does it instead. Nothing here is flashed, rooted or uninstalled.
#
# This file is deliberately ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI unless the file
# has a BOM, and a mis-decoded Chinese string literal breaks the parser. Chinese notes live in
# docs/guard.md.
#
# Usage (from the repository root, with cleanyourtv's Python ADB client set up):
#   powershell -ExecutionPolicy Bypass -File scripts\watch-home.ps1 -TvHost 192.168.1.50
#   powershell -ExecutionPolicy Bypass -File scripts\watch-home.ps1 -TvHost 192.168.1.50 -IntervalSeconds 5
#   ... -NoKill        keep the stock home running (costs ~115% CPU, ~280 MB)
#   ... -NoLiveTv      do not open a live TV app at boot
#   ... -LiveTv <component>   which activity to open instead
#
# Ctrl+C to stop.

param(
    [Parameter(Mandatory = $true)]
    [string]$TvHost,
    [int]$IntervalSeconds = 5,
    [switch]$NoKill,
    [string]$LiveTv = 'com.tntlikely.xplayer/com.tntlikely.xplayer.MainActivity',
    [switch]$NoLiveTv,
    [string]$RepoRoot = ''
)

# Locate the cleanyourtv checkout: -RepoRoot, else a sibling folder, else ../cleanyourtv
if (-not $RepoRoot) {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\cleanyourtv'),
        (Join-Path $PSScriptRoot '..\..\cleanyourtv')
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'tools\tv.py')) { $RepoRoot = (Resolve-Path $c).Path; break }
    }
}
if (-not $RepoRoot -or -not (Test-Path (Join-Path $RepoRoot 'tools\tv.py'))) {
    Write-Host 'ERROR: cleanyourtv checkout not found. Pass -RepoRoot <path to cleanyourtv>.'
    exit 2
}

$py = Join-Path $RepoRoot 'tools\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    Write-Host ('ERROR: {0} missing. Create it: python -m venv tools\venv; tools\venv\Scripts\pip install -r tools\requirements.txt' -f $py)
    exit 2
}
$tvpy = Join-Path $RepoRoot 'tools\tv.py'
$env:TV_HOST = $TvHost

$launcher = 'com.coocaa.tvhome/com.gathin.tvhome.MainActivity'
$launcherPkg = 'com.coocaa.tvhome'
$stockHome = 'com.tianci.movieplatform'

# Packages the firmware has been seen re-enabling by itself (com.tianci.ad came back once after a
# reboot). Checked every AdGuardEvery cycles and disabled again. Disable, never uninstall.
$AdPackages = @('com.tianci.ad', 'com.coocaa.guide', 'com.skyworth.skymarket')
$AdGuardEvery = 12

function Run-Tv([string]$cmd) {
    & $py -I $tvpy $cmd 2>&1 | Out-String
}

Write-Host ('[watch-home] TV={0}  interval={1}s  kill-stock={2}  live-tv={3}' -f `
        $TvHost, $IntervalSeconds, (-not $NoKill), $(if ($NoLiveTv) { 'off' } else { $LiveTv }))

$lastState = ''
$stockRunning = $false
$liveTvBoot = -1           # boot_count whose live TV actually came up
$liveTvTryBoot = -1        # boot_count the attempts below belong to
$liveTvTries = 0
$liveTvGaveUp = $false
$pendingLiveTv = $false
$cycle = 0

while ($true) {
    $stamp = Get-Date -Format 'HH:mm:ss'
    $focus = (Run-Tv 'dumpsys window | grep mCurrentFocus').Trim()

    if ($focus -match 'error|refused|timed out|Timeout|Exception') {
        if ($lastState -ne 'offline') {
            Write-Host ('[{0}] TV not reachable, waiting...' -f $stamp)
            $lastState = 'offline'
        }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    if ($focus -match [regex]::Escape($stockHome)) {
        Write-Host ('[{0}] stock Coocaa home in front -> taking over' -f $stamp)
        [void](Run-Tv ('setprop persist.service.homepage.pkg ' + $launcherPkg))
        [void](Run-Tv ('setprop persist.service.homepage.cls com.gathin.tvhome.MainActivity'))
        $r = (Run-Tv ('am start -n ' + $launcher)).Trim()
        Write-Host ('           ' + (($r -split "`n") | Select-Object -First 1))
        if (-not $NoKill) {
            Start-Sleep -Milliseconds 800
            [void](Run-Tv ('am force-stop ' + $stockHome))
            Write-Host '           stock home force-stopped'
        }
        $lastState = 'redirected'
        $stockRunning = $false
    }
    elseif ($focus -match [regex]::Escape($launcherPkg)) {
        if (-not $NoKill) {
            $ps = (Run-Tv ('ps -A | grep ' + $stockHome)).Trim()
            if ($ps -and $ps -notmatch 'grep') {
                if (-not $stockRunning) {
                    Write-Host ('[{0}] stock home running behind the launcher -> force-stopping it' -f $stamp)
                    $stockRunning = $true
                }
                [void](Run-Tv ('am force-stop ' + $stockHome))
            }
            elseif ($stockRunning) {
                Write-Host ('[{0}] stock home gone' -f $stamp)
                $stockRunning = $false
            }
        }

        # Live TV once per boot. The firmware can restore the previous task over it a second or two
        # after the launcher comes up, so retry a few times -- only while the launcher is in front,
        # so an app the viewer opened is never pulled away.
        if (-not $NoLiveTv) {
            $boot = (Run-Tv 'settings get global boot_count').Trim()
            if ($boot -match '^\d+$' -and [int]$boot -ne $liveTvBoot) {
                if ($boot -ne $liveTvTryBoot) {
                    $liveTvTryBoot = [int]$boot
                    $liveTvTries = 0
                }
                if ($liveTvTries -lt 3) {
                    $liveTvTries++
                    Write-Host ('[{0}] boot #{1}, live TV attempt {2}/3' -f $stamp, $boot, $liveTvTries)
                    $r = (Run-Tv ('am start -n ' + $LiveTv)).Trim()
                    Write-Host ('           ' + (($r -split "`n") | Select-Object -First 1))
                    if ($r -match 'Starting: Intent|Status: ok') { $pendingLiveTv = $true }
                }
                elseif (-not $liveTvGaveUp) {
                    Write-Host ('[{0}] live TV did not take; leaving Home alone' -f $stamp)
                    $liveTvGaveUp = $true
                }
            }
        }

        if ($lastState -ne 'ok') {
            Write-Host ('[{0}] launcher in front, standing by' -f $stamp)
            $lastState = 'ok'
        }
    }
    else {
        if ($pendingLiveTv) {
            Write-Host ('[{0}] live TV is up' -f $stamp)
            $pendingLiveTv = $false
            $boot = (Run-Tv 'settings get global boot_count').Trim()
            if ($boot -match '^\d+$') { $liveTvBoot = [int]$boot }
        }
        # Some other app or an input source is in front: leave it alone.
        $lastState = 'other'
    }

    $cycle++
    if ($cycle % $AdGuardEvery -eq 0) {
        $disabled = (Run-Tv 'pm list packages -d')
        foreach ($ad in $AdPackages) {
            if ($disabled -notmatch [regex]::Escape($ad)) {
                Write-Host ('[{0}] firmware re-enabled {1} -> disabling it again' -f $stamp, $ad)
                [void](Run-Tv ('pm disable-user --user 0 ' + $ad))
            }
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
