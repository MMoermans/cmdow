# Runs cmdow against a real window and checks the result with an independent probe.
#   run-tests.ps1 -Cmdow .\cmdow.exe -TestWin .\tests\testwin.exe -Probe .\tests\probe.exe
param(
    [Parameter(Mandatory)][string]$Cmdow,
    [Parameter(Mandatory)][string]$TestWin,
    [Parameter(Mandatory)][string]$Probe
)

$ErrorActionPreference = 'Stop'
$caption = 'cmdow-test-window'
$script:failed = 0

function Check([string]$name, [bool]$condition, [string]$detail = '') {
    if ($condition) { "ok    $name" }
    else { "FAIL  $name  $detail"; $script:failed++ }
}

function Get-State {
    $state = @{}
    foreach ($line in (& $Probe $caption)) {
        $key, $value = $line -split '=', 2
        $state[$key] = [long]$value
    }
    $state
}

# Run cmdow, return its combined output and exit code
function Invoke-Cmdow {
    $ErrorActionPreference = 'Continue'   # cmdow reports errors on stderr, which is not a script error
    $out = & $Cmdow @args 2>&1 | Out-String
    [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

function Settle { Start-Sleep -Milliseconds 400 }

# --- start the test window --------------------------------------------------------------------
$proc = Start-Process -FilePath $TestWin -PassThru
try {
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 250
        $s = Get-State
    } until ($s['found'] -eq 1 -or (Get-Date) -gt $deadline)
    Check 'test window is up' ($s['found'] -eq 1)
    if ($s['found'] -ne 1) { throw 'test window did not appear' }
    $s = Get-State
    Check 'window starts opaque (not layered)' ($s['layered'] -eq 0)

    # --- /TRN -----------------------------------------------------------------------------------
    $r = Invoke-Cmdow $caption /TRN 50
    Check '/TRN 50 exits 0' ($r.Code -eq 0) $r.Out
    $s = Get-State
    Check '/TRN 50 makes the window layered' ($s['layered'] -eq 1)
    Check '/TRN 50 sets alpha 128' ($s['alpha'] -eq 128) "alpha=$($s['alpha'])"

    $null = Invoke-Cmdow $caption /TRN 1
    Check '/TRN 1 sets alpha 3' ((Get-State)['alpha'] -eq 3)

    $null = Invoke-Cmdow $caption /TRN 100
    Check '/TRN 100 restores alpha 255' ((Get-State)['alpha'] -eq 255)

    $null = Invoke-Cmdow $caption /TRN 25
    foreach ($bad in '0', '101', 'abc', '-5', '5x', '') {
        $r = Invoke-Cmdow $caption /TRN $bad
        Check "/TRN '$bad' is rejected" ($r.Code -eq 1 -and $r.Out -match 'opacity percentage') $r.Out
    }
    $r = Invoke-Cmdow $caption /TRN
    Check '/TRN without a value is rejected' ($r.Code -eq 1 -and $r.Out -match 'opacity percentage')
    Check 'rejected /TRN leaves the window alone' ((Get-State)['alpha'] -eq 64) "alpha=$((Get-State)['alpha'])"
    $null = Invoke-Cmdow $caption /TRN 100

    # --- /CEN -----------------------------------------------------------------------------------
    $r = Invoke-Cmdow $caption /MOV 20 30 /SIZ 400 300 /CEN
    Check '/MOV /SIZ /CEN exits 0' ($r.Code -eq 0) $r.Out
    $s = Get-State
    Check '/CEN keeps the size' (($s['right'] - $s['left']) -eq 400 -and ($s['bottom'] - $s['top']) -eq 300)
    Check '/CEN centres horizontally' ([math]::Abs(($s['left'] - $s['work_left']) - ($s['work_right'] - $s['right'])) -le 1) ($s | Out-String)
    Check '/CEN centres vertically' ([math]::Abs(($s['top'] - $s['work_top']) - ($s['work_bottom'] - $s['bottom'])) -le 1) ($s | Out-String)

    # --- /SNAP ----------------------------------------------------------------------------------
    $null = Invoke-Cmdow $caption /SNAP left
    $s = Get-State
    $cx = $s['work_right'] - $s['work_left']; $cy = $s['work_bottom'] - $s['work_top']
    Check '/SNAP left: left edge' ($s['left'] -eq $s['work_left'] -and $s['top'] -eq $s['work_top'])
    Check '/SNAP left: half the width, full height' (($s['right'] - $s['left']) -eq [math]::Floor($cx / 2) -and ($s['bottom'] - $s['top']) -eq $cy) ($s | Out-String)

    $null = Invoke-Cmdow $caption /SNAP right
    $s = Get-State
    Check '/SNAP right: right edge' ($s['right'] -eq $s['work_right'] -and $s['top'] -eq $s['work_top'])
    Check '/SNAP right: half the width' (($s['right'] - $s['left']) -eq ($cx - [math]::Floor($cx / 2)) -and ($s['bottom'] - $s['top']) -eq $cy)

    $null = Invoke-Cmdow $caption /SNAP top
    $s = Get-State
    Check '/SNAP top: top edge, full width' ($s['top'] -eq $s['work_top'] -and $s['left'] -eq $s['work_left'] -and ($s['right'] - $s['left']) -eq $cx)
    Check '/SNAP top: half the height' (($s['bottom'] - $s['top']) -eq [math]::Floor($cy / 2))

    $null = Invoke-Cmdow $caption /SNAP BOTTOM
    $s = Get-State
    Check '/SNAP BOTTOM is case insensitive, bottom edge' ($s['bottom'] -eq $s['work_bottom'] -and $s['left'] -eq $s['work_left'] -and ($s['right'] - $s['left']) -eq $cx)

    foreach ($bad in 'middle', '') {
        $r = Invoke-Cmdow $caption /SNAP $bad
        Check "/SNAP '$bad' is rejected" ($r.Code -eq 1 -and $r.Out -match 'left, right, top or bottom') $r.Out
    }
    $r = Invoke-Cmdow $caption /SNAP
    Check '/SNAP without a value is rejected' ($r.Code -eq 1 -and $r.Out -match 'left, right, top or bottom')

    # --- combining with existing actions -----------------------------------------------------------
    $r = Invoke-Cmdow $caption /SIZ 300 200 /CEN /TRN 80
    $s = Get-State
    Check 'tasks run left to right: /SIZ then /CEN then /TRN' (($s['right'] - $s['left']) -eq 300 -and $s['alpha'] -eq 204 -and
        [math]::Abs(($s['left'] - $s['work_left']) - ($s['work_right'] - $s['right'])) -le 1) ($s | Out-String)

    # --- minimized windows are left alone ----------------------------------------------------------
    $null = Invoke-Cmdow $caption /RES /MOV 10 10 /SIZ 300 200
    Settle
    $null = Invoke-Cmdow $caption /MIN
    Settle
    $r = Invoke-Cmdow $caption /CEN
    Check '/CEN on a minimized window is a no-op that still exits 0' ($r.Code -eq 0) $r.Out
    $null = Invoke-Cmdow $caption /RES
    Settle
    $s = Get-State
    Check '/CEN did not move a minimized window' ($s['left'] -eq 10 -and $s['top'] -eq 10) ($s | Out-String)

    # --- help ---------------------------------------------------------------------------------------
    $r = Invoke-Cmdow /?
    Check 'help lists the new commands and version' ($r.Code -eq 0 -and $r.Out -match '/TRN' -and $r.Out -match '/CEN' -and $r.Out -match '/SNAP' -and $r.Out -match '1\.5\.0') $r.Out
    foreach ($topic in '/TRN', '/CEN', '/SNAP') {
        $r = Invoke-Cmdow /? $topic
        Check "/? $topic shows the detail page" ($r.Code -eq 0 -and $r.Out -match 'Centres the specified window' -and $r.Out -match 'opacity') $r.Out
    }
    $widest = ((Invoke-Cmdow /?).Out + (Invoke-Cmdow /? /TRN).Out) -split "`r?`n" | ForEach-Object { $_.Length } | Measure-Object -Maximum
    Check 'help fits in 80 columns' ($widest.Maximum -le 80) "widest=$($widest.Maximum)"

    # --- existing behaviour still works ---------------------------------------------------------------
    $r = Invoke-Cmdow $caption /P /B
    Check 'listing a window still works' ($r.Code -eq 0 -and $r.Out -match 'testwin')
    $r = Invoke-Cmdow $caption /TRN 50 /MOV
    Check 'a missing /MOV argument is still reported' ($r.Code -eq 1 -and $r.Out -match '/MOV')
    $r = Invoke-Cmdow /CEN
    Check '/CEN without a window is rejected' ($r.Code -eq 1) $r.Out
    $r = Invoke-Cmdow $caption /CEN /LIST
    Check 'unknown arguments are still rejected' ($r.Code -eq 1)

    # --- close ----------------------------------------------------------------------------------------
    $null = Invoke-Cmdow $caption /CLS
    $exited = $proc.WaitForExit(10000)
    Check '/CLS still closes the window' $exited
}
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
}

if ($script:failed) { "`n$($script:failed) check(s) failed"; exit 1 }
"`nall checks passed"
